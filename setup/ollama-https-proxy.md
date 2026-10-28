# Ollama con proxy HTTPS

Notas de cómo he montado Ollama para que SQL Server 2025 pueda usarlo. SQL Server solo llama a servicios HTTPS y Ollama sirve en HTTP, así que he puesto nginx delante con un certificado local de mkcert.

Los certificados no están en el repositorio (el `.gitignore` excluye `*.pem`), así que hay que generar los propios.

## 1. Ollama y el modelo de embeddings

```powershell
ollama pull nomic-embed-text
```

Para probarlo, desde una carpeta que no sea la del repositorio (por ejemplo `C:\nginx`), guardo el cuerpo de la petición en un archivo y lo envío con curl directamente a Ollama:

```powershell
'{"model":"nomic-embed-text","input":"prueba"}' | Out-File -Encoding ascii body.json
curl.exe http://localhost:11434/api/embed -H "Content-Type: application/json" -d "@body.json"
```

Uso el archivo porque PowerShell estropea las comillas dobles cuando se las pasa a `curl.exe`. En el Símbolo del sistema (cmd) sí se puede escribir el JSON en la misma línea.

Si devuelve una lista larga de números, funciona. `nomic-embed-text` da vectores de 768 dimensiones, que es lo que luego se usa en `VECTOR(768)`.

## 2. Certificado local

En PowerShell como administrador:

```powershell
winget install FiloSottile.mkcert
mkcert -install
mkdir C:\certs
cd C:\certs
mkcert localhost 127.0.0.1 ::1
```

El servicio de SQL Server no corre con tu usuario, así que hay que importar la entidad certificadora en el almacén del equipo y reiniciar el servicio de SQL Server:

```powershell
certutil -addstore -f "ROOT" "$(mkcert -CAROOT)\rootCA.pem"
```

## 3. nginx

Descargar nginx para Windows desde nginx.org, descomprimirlo en `C:\nginx` y copiar [nginx.conf](nginx.conf) a `C:\nginx\conf\nginx.conf`. Después:

```powershell
cd C:\nginx
start nginx
curl.exe --ssl-no-revoke https://localhost:11435/api/embed -H "Content-Type: application/json" -d "@body.json"
```

En PowerShell hay que escribir `.\nginx` en lugar de `nginx` (y `start .\nginx`). El `body.json` es el del paso 1, así que hay que lanzarlo desde la misma carpeta.

`--ssl-no-revoke` hace falta porque los certificados de mkcert no llevan información de revocación y curl en Windows se queja. Para parar nginx: `nginx -s stop`.

## 4. SQL Server

Ejecutar [00_verificar_entorno.sql](00_verificar_entorno.sql).

Ollama y nginx tienen que estar en marcha cada vez que se trabaje con la parte de IA.

## Deshacerlo

```powershell
cd C:\nginx
nginx -s stop
mkcert -uninstall
```

Después hay que borrar `C:\certs` y la carpeta que muestra `mkcert -CAROOT`, quitar el certificado de mkcert de las entidades raíz del equipo (`certlm.msc`) y, en SQL Server, ejecutar `EXEC sp_configure 'external rest endpoint enabled', 0; RECONFIGURE WITH OVERRIDE;`.

## Seguridad

nginx escucha solo en `127.0.0.1` para no exponer Ollama a la red. La clave privada de la entidad certificadora de mkcert no se comparte ni se sube a ningún sitio.
