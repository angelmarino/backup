# backup
Copias de seguridad
## Antes de empezar hay que configurar en el servidor la keygen y dejarlo que se pueda conectar de forma automática al servidor de backup.
# ssh-keygen -t rsa -b 4096
# ssh-copy-id -i ~/.ssh/id_rsa user@miservidor.com

# Si es un Plesk
# backup plesk all   >> Realizará un backup de todos los ficheros y bases de datos
# backup plesk db    >> Realizará un backup de todas las bases de datos
# backup plesk files >> Realizará un backup de todos los ficheros

# Si es un servidor sin panel de control / custom
# backup custom all                      >> Hará un backup de todos los archivos y base de datos, Es importante que el usuario de base de datos
# backup custom files mipaginsweb.com    >> Hará un backup de un sitio web en concreto.
# backup custom db nombredb              >> Hará un backup de un sitio web en concreto.
