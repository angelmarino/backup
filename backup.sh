#!/bin/bash
export PATH=/bin:/usr/bin:/usr/local/bin
################################################################
##
##   Sistema de copia de seguridad completa
##   Escrito por: Angel Luis Marino
##   Creación: 11-11-2019
##   Actualización: 16-07-2021
##
################################################################

## Antes de empezar hay que configurar en el servidor la keygen y dejarlo que se pueda conectar de forma automatica al servidor de backup.
# ssh-keygen -t rsa -b 4096
# ssh-copy-id -i ~/.ssh/id_rsa user@miservidor.com
# 82Gak4u$vL324k~p

# Si es un Plesk
# backup plesk all   >> Realizará un backup de todos los ficheros y bases de datos
# backup plesk db    >> Realizará un backup de todas las bases de datos
# backup plesk files >> Realizará un backup de todos los ficheros

# Si es un servidor sin panel de control / custom
# backup custom all                      >> Hará un backup de todos los archivos y base de datos, Es importante que el usuario de base de datos
# backup custom files mipaginsweb.com    >> Hará un backup de un sitio web en concreto.
# backup custom db nombredb              >> Hará un backup de un sitio web en concreto.

datetime=$(date +"%d-%m-%Y %H:%M:%S")
datetime_dir=$(date +"%d-%m-%Y")

ads="Angel Luis"

## Numero de dias de retencion de la copia de seguridad
BACKUP_RETAIN_DAYSLocal=1
BACKUP_RETAIN_DAYS=5               º

##### Eliminamos backups antiguos  #####
DELDATE=$(date +"%d-%m-%Y" --date="${BACKUP_RETAIN_DAYSLocal} days ago")

porcentaje_seguro_backup="70"
porcentaje_remote_backup="95"

if [ "$2" == 'file' ]; then
   tipobackup=$3
elif [ "$2" == 'db' ]; then
   tipobackup=$3
fi;

### Parametros mysql
MYSQL_HOST='localhost'
#MYSQL_PORT='3306'
MYSQL_USER='backup'
MYSQL_PASSWORD='B@ck_264350.**'

# Backup en bases de datos docker
docker_contenedor="containername"
docker_localhost_db="localhost"
docker_username_db="localhost"
docker_password_db="localhost"
docker_database=${tipobackup}

# Pámetros de entrada
sitioweb=$3
DATABASE_NAME=$3

# Servidor de backup remoto
server_backup="miservidor" # Servidor remoto de copias de seguridad.
server_usuario="usuario"               # usuario del servidor remoto
server_path_file="cloud/"                # Carpeta remota de destino de copia de seguridad.
server_typefile="var"                    # Tipo de sistema de archivo en el servidor remoto, generalmente es donde está la mayoria del almacenamiento.
verifica_espacio_remoto="ko"             # Inicamos con ok, si queremos que verifique el espacio remoto.
verifica_espacio_local="ko"              # Iniciamos con ok, si vamos a verificar el espacio local.
id_rsa="/root/.ssh/id_rsa.pub"

plesk_destino_backup_db="/var/www/vhosts/" # Destino de copias de seguridad en plesk

# Destino temporal de copias de seguridad.
# Está carpeta será creada si no existe, y desntro de ella las carpetas de mysql y files
backup="/var/www/backup/"
DB_BACKUP_PATH=${backup}"mysql/"       # Destino de copia de seguridad mysql
FILES_BACKUP_PATH=${backup}"ficheros/" # Destino de copia de seguridad de ficheros

# Dentro de cada una de ellas cada copia se seguridad se organizarán en cada carpeta con la fecha de creación
dbfiledia=${DB_BACKUP_PATH}/${datetime_dir}
filedia=${FILES_BACKUP_PATH}/${datetime_dir}

# Origen de la copia de seguridad.
#
origen_custom="/var/www/${sitioweb}/web/"
origen_plesk="/var/www/vhosts/"

# Función de registro de errores
registro() {
  ## Registro del proceso de copia de seguridad
  file_log=/var/log/backups.log
  horafecha=$(date +"%d-%m-%Y %H:%M:%S")
  echo "${horafecha} - $1" >>$file_log
}

# Verificamos que hay parametros de entrada.
if [ $# == '2' ]; then
  if [ "$1" != 'plesk' ]; then
    registro "Parametros incorrectos"
    continua=0
  elif [ "$1" != 'vesta' ]; then
    registro "Parametros incorrectos"
    continua=0
  elif [ "$1" != 'custom' ]; then
    registro "Parametros incorrectos"
    continua=0
  else
    registro "Iniciando backup del ${datetime_dir} por ${ads}"
    continua=1
  fi

  if [ ${continua} == 0 ]; then exit; fi

else
  registro "Parametros incorrectos"
  exit
fi

# Verificamos que el id_rsa existe
# Necesario para enviar la copia de seguridad.
if [ ! -r $id_rsa ]; then
  registra "El id rsa no exite, por favor configura el servidor con uno."
  exit
fi

verificar_espacio() {
  # Verificamos que el espacio en $disco uso es mayor que el porcentaje por defecto.

  if [ "$1" == 'local' ]; then
    discouso=$(df -h | grep -E "/$2" | tr -s ' ' | cut -d' ' -f5 | tr -d %)
    if [ "${discouso}" -gt "${porcentaje_seguro_backup}" ]; then
      registro "Abortamos copia de seguridad por falta de espacio en disco - $2"
      exit
    fi
  elif [ "$1" == 'remote' ]; then
    uso_disco_remoto=$(ssh ${server_usuario}@${server_backup} "df -h | grep -E '/$2' | tr -s ' ' | cut -d' ' -f5 | tr -d %")
    registro "${uso_disco_remoto}% usado remote $2 "
    # Verificamos que el espacio en $disco uso es mayor que el porcentaje por defecto.
    if [ "${uso_disco_remoto}" -gt "${porcentaje_remote_backup}" ]; then
      registro "Abortamos copia de seguridad por falta de espacio en disco - $2"
      exit
    fi
  fi
}

elimina_backs_antiguos() {

  # ${FILES_BACKUP_PATH} => $1
  # ${DELDATE} => $2

  # Ficheros
  if [ -z "$1" ]; then
    cd "$1" || registro "$1 No existe"
    if [ -z "$2" ] && [ -d "$2" ]; then
      rm -rf "$2"
      registro "Se ha eliminado el backup $3 $2 en $1"
    else
      registro "Nada por eliminar de fichero $2"
    fi
  fi
}

# Generamos archivo de configuracion para acceder a la base de datos.
config_mysql() {
  # Estos datos los guardamos en un fichero temporal para no lanzar errores.
  mysql_credenciales="/root/access-mysql.conf"

  # Creamos el fichero de configuración con los accesos
  touch ${mysql_credenciales}

  # Contenido a escribir en el fichero,
  {
    "[client]"
    "user=${MYSQL_USER}"
    "password=${MYSQL_PASSWORD}"
    "host=${MYSQL_HOST}"
  } >>${mysql_credenciales}

  # retornamos la ubicación para despues eliminarla.
  return ${mysql_credenciales}
}

# Verificamos que el directorio de backup exite y sino lo creamos
if [ ! -e ${backup} ]; then
  mkdir ${backup}
  mkdir -p "${dbfiledia}"
  mkdir -p "${filedia}"
  registro "Creación de carpeta de backup ${backup}"

elif [ ! -e "${dbfiledia}" ]; then
  mkdir -p "${dbfiledia}"
  registro "Creación de carpeta de backup ${dbfiledia}"

elif [ ! -e "${filedia}" ]; then
  mkdir -p "${filedia}"
  registro "Creación de carpeta de backup ${filedia}"

elif [ ! -d ${backup} ]; then
  registro "${backup} exite"
fi

registro "Revisando backups antiguos ${DELDATE}"

# Eliminar backup antiguos en local
elimina_backs_antiguos ${DB_BACKUP_PATH} "${DELDATE}" 'mysql'
elimina_backs_antiguos ${FILES_BACKUP_PATH} "${DELDATE}" 'ficheros'

# Acción a realizar si el servidor es plesk
plesk_backup_db() {
  registro "Backup de base de datos iniciado - ${DATABASE_NAME}"
  # Recojemos el bucle completo del listado de base de datos.
  for DB in $(MYSQL_PWD=$(cat /etc/psa/.psa.shadow) mysql -u admin -e 'show databases' -s --skip-column-names); do
    # Bamos haciendo el backup de cada base de datos comprimidas en gzip
    MYSQL_PWD=$(cat /etc/psa/.psa.shadow) mysqldump --single-transaction=TRUE --lock-tables=false -uadmin "$DB" | gzip >"${plesk_destino_backup_db}$DB.sql.gz"
  done
}

plesk_backup_files() {

  for i in $(plesk bin subscription --list); do
    backup_files "plesk" "$i" "no"
  done
}

# Función de backup genérico de copia de seguridad.
backup_db() {

  local login_mysql
  login_mysql="$(config_mysql)"
  registro "Backup de base de datos iniciado - ${DATABASE_NAME}"
  # Generamos archivos de configuración



  if mysqldump --defaults-extra-file="$login_mysql" "${DATABASE_NAME}" | gzip >"${dbfiledia}/${DATABASE_NAME}-${datetime_dir}.sql.gz"; then

    registro "Backup mysql realizado correctamente"
    rm "${login_mysql}"

    # Iniciamos la subido a un servidor remoto
    if rsync -rv --delete "${dbfiledia}/${DATABASE_NAME}-${datetime_dir}.sql.gz" ${server_usuario}@${server_backup}:${server_path_file} >>"$LOG_FILE"; then
      registro "${datetime} - Base de datos subida correctamente al servidor con el nombre ${DATABASE_NAME}-${datetime_dir}.sql.gz"
    else
      registro "${datetime} - Error en la subida"
    fi

  else

    registro "Error en el proceso de backup, fallo en el dump $?"
    exit 1
  fi
}

backup_mysql_docker() {
  BACKUP_FILE_NAME="$(date +"%d-%m-%y-%H%M%S.sql.gz")"
  if ! docker exec ${docker_contenedor} bash -c 'exec mysqldump --databases "${docker_database}" -h"${docker_localhost_db}" -u"${docker_username_db}" -p"${docker_password_db}"' | gzip >"${dbfiledia}"/"$BACKUP_FILE_NAME"; then
    registro "Fallo en el docker $?"
  fi
}

backup_files() {

  # Backup de archivos en plesk panel
  comprimido_dest="${FILES_BACKUP_PATH}/${datetime_dir}/$2/$2-${datetime_dir}.tar.gz"
  if [ "$1" == 'plesk' ]; then
    # Origen de la copia de seguridad, añadiendo la suscripción
    plesk_origen="${origen_plesk}$2"
    # Nos situamos en el directorio de origen
    #cd ${origen_plesk} || registro "el origen del $plesk_origen backup plesk no existe"
    registro "Backup iniciado - $1 de $plesk_origen a ${comprimido_dest}"

    if [ "$3" == 'exclude' ]; then
      tar --exclude="$4" -cjf "${comprimido_dest}" "$plesk_origen"
    else
      tar -cjf "${comprimido_dest}" "$plesk_origen"
    fi

  # Backup de archivos en servidor custom
  elif [ "$1" == 'custom' ]; then
    #cd ${origen_custom} || registro "el origen del $origen_custom backup custom no existe"
    registro "Backup iniciado - $1 ${comprimido_dest} desde ${origen_custom}"

    if [ "$3" == 'exclude' ]; then
      tar --exclude="$4" -cjf "${comprimido_dest}" "${origen_custom}"
    else
      tar -cjf "${comprimido_dest}" "${origen_custom}"
    fi

  fi

}

subir_ficheros() {
  # Subida de ficheros a traves de rsync
  if rsync -rv "$1" ${server_usuario}@${server_backup}:${server_path_file} >>"$LOG_FILE"; then
    registro "Ficheros subidos correctamente al servidor"
  else
    registro "Error en la subida de ficheros $?"
  fi
}

# backup de servidor plesk
if [ "$1" == 'plesk' ]; then

  if [ ${verifica_espacio_remoto} == "ok" ]; then
    # Verificar el el repositorio de backup remoto es plesk
    verificar_espacio "remote" ${server_typefile}
  fi

  if [ ${verifica_espacio_local} == "ok" ]; then
    # Verificar espacio local
    verificar_espacio "local" ${server_typefile}
  fi
  ## Backup de todos los ficheros y bases de datos
  if [ "$2" == 'all' ]; then
    # backup de servidor plesk
    plesk_backup_db
    plesk_backup_files

  ## Backup de todos los ficheros
  elif [ "$2" == 'files' ]; then
    # backup de servidor plesk
    plesk_backup_files

  ## Backup de bases de datos
  elif [ "$2" == 'db' ]; then
    # backup de servidor plesk
    plesk_backup_db
  fi
  exit
  # Fin de copia de plesk

elif [ "$1" == 'vesta' ]; then
  # backupo de servidor vestacp or hestiacp
  echo "Parametros insuficientes $#"
  exit

elif [ "$1" == 'custom' ]; then
  ## Backup de servidor web sin panel de control

  backup_db
  backup_files "custom" "${sitioweb}" "sinexcluir"
  #backup_files "exclude" {"",""}

elif [ "$1" == 'docker' ]; then
  backup_mysql_docker "db" "data"  # De momento hacesmos copia de todas las bases de datos de docker

fi;

registro "Backup del ${datetime_dir} por ${ads}"
