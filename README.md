# Mini-SCADA con SQL Server 2025

Mini proyecto de Big Data para practicar lo de la certificación DP-800 (SQL AI Developer Associate). Voy a por el nivel 3 del enunciado: diseño de base de datos, seguridad y optimización, embeddings, búsqueda vectorial y un RAG con modelo local.

Elegí este tema ya que trabajé en una empresa dedicada al sector del IoT, concretamente en diseños y remodelaciones de edificios inteligentes. Tengo experiencia creando y utilizando sistemas SCADA.
Lo que espero aprender de este proyecto es a integrar inteligencia artificial para detectar incidencias, basándose en anteriores sucesos de ese mismo sistema, y además poder consultar esa información en lenguaje natural.

Todavía está en desarrollo y voy actualizando este README según avanzo.

## De qué va

Una base de datos en SQL Server 2025 que guarda lecturas de sensores, alarmas, incidencias y manuales de equipos IoT, como haría un SCADA pequeño. Los datos los simulo con un script.

Sobre eso quiero poder preguntar en lenguaje natural, por ejemplo "el sensor de CO2 marca siempre lo mismo", y que SQL Server encuentre las alarmas parecidas y el manual que toca por significado y no por palabras exactas. Después, un modelo local redacta la respuesta con lo que ha encontrado (RAG).


## Cómo lo planteo

```
Usuario -> procedimientos T-SQL -> SQL Server 2025 (tablas, vectores, seguridad)
                                        |
                                      HTTPS
                                        |
                              nginx (proxy local) -> Ollama
```

SQL Server solo llama a servicios HTTPS y Ollama habla HTTP, por eso hay un proxy en medio. Cuando tenga el diagrama definitivo lo cambiaré por una imagen.

<!-- FASE 5: guarda el diagrama como docs/images/arquitectura.png y sustituye el bloque de arriba por la línea ![Arquitectura](docs/images/arquitectura.png). -->

## Tecnologías

Todo funciona en local, en mi portátil con Windows 11:

- SQL Server 2025 (RTM, versión 17.0.1000.7) y T-SQL
- SQL Server Management Studio (SSMS) 22.10.2
- Ollama 0.40.9, con el modelo de embeddings `nomic-embed-text` (vectores de 768 dimensiones) y un LLM pequeño para el RAG
- nginx 1.30.6 y mkcert 1.4.4 para el proxy HTTPS local
- Git y GitHub

## Montar el entorno

Esta fue la parte que más tiempo me llevó, y no tuvo nada que ver con SQL sino con conseguir que SQL Server hablara con Ollama. SQL Server 2025 solo llama a servicios por HTTPS y Ollama sirve en HTTP, así que tuve que poner un proxy en medio. Al final el orden que me funcionó fue este:

1. Ollama y el modelo `nomic-embed-text`, probado primero con curl directamente contra Ollama.
2. mkcert para crear un certificado local, e importar su entidad certificadora en el almacén del equipo. SQL Server corre como servicio y no usa los certificados de mi usuario, y eso me costó entenderlo.
3. nginx escuchando en `https://127.0.0.1:11435` y reenviando todo a Ollama.
4. En SQL Server, activar las llamadas REST externas, comprobar que llegan al proxy, crear el modelo externo y generar un primer vector.

Los pasos con los comandos están en [setup/ollama-https-proxy.md](setup/ollama-https-proxy.md), y las comprobaciones en SQL en [setup/00_verificar_entorno.sql](setup/00_verificar_entorno.sql).

### Lo que me fue fallando

- **curl se quejaba de la revocación del certificado** (`CRYPT_E_NO_REVOCATION_CHECK`). Los certificados de mkcert no llevan información de revocación y curl en Windows lo exige. Se arregla con `--ssl-no-revoke`.
- **mkcert y nginx "no se reconocen" en PowerShell.** mkcert hacía falta cerrar y abrir la terminal después de instalarlo con winget, y nginx en PowerShell hay que lanzarlo como `.\nginx`.
- **El JSON de curl en PowerShell.** PowerShell estropea las comillas dobles, y curl daba errores raros como "invalid character" o "Port number was not a decimal number". Lo resolví guardando el cuerpo de la petición en un `body.json` y enviándolo con `-d "@body.json"`.
- **No sabía si la llamada había funcionado.** Al ejecutar `sp_invoke_external_rest_endpoint` solo me ponía "Los comandos se han completado correctamente". Resulta que la respuesta no sale como tabla sino por el parámetro `@response OUTPUT`, así que hay que guardarla en una variable y sacarla con un `SELECT`. Una vez hecho eso se ve `CodigoRetorno` 0 y `"code":200`.

### Cómo comprobé que funciona

Primero la versión de SQL Server:

![Versión de SQL Server](docs/images/00_version.png)

Después el proxy, con curl, devolviendo el vector de `nomic-embed-text`:

![curl al proxy](docs/images/00_curl_proxy.png)

La llamada desde SQL Server al proxy, con código de retorno 0 y el 200 en la respuesta:

![Llamada REST desde SQL Server](docs/images/00_llamada_rest.png)

El modelo externo creado dentro de la base de datos `MiniScada`, con la consulta a `sys.external_models`:

![Modelo externo](docs/images/00_modelo_externo.png)

Y el primer vector generado con `AI_GENERATE_EMBEDDINGS` a partir de una frase de prueba:

![Vector de prueba](docs/images/00_vector.png)

## Base de datos

La base de datos se llama `MiniScada` y tiene 8 tablas. El script que las crea está en [database/01_tablas.sql](database/01_tablas.sql) y se puede ejecutar entero las veces que haga falta, porque borra y vuelve a crear las tablas.

![Diagrama de la base de datos](docs/images/01_diagrama_bd.png)

| Tabla | Para qué sirve |
| --- | --- |
| Zonas | Áreas o edificios donde están los equipos. Guarda un email de contacto, que más adelante enmascaro |
| Dispositivos | Nodos IoT de cada zona, con su modelo y su estado |
| Sensores | Sensores de cada dispositivo: qué miden, en qué unidad y su rango normal (mínimo y máximo) |
| Lecturas | Histórico de mediciones: sensor, fecha, valor y el mensaje JSON original. Es la tabla grande |
| Alarmas | Eventos anómalos de un sensor, con severidad, estado y su embedding |
| Incidencias | Cómo se resolvió cada alarma: responsable, causa y solución |
| Documentos | Manuales y procedimientos, con su embedding |
| UsuariosZona | Qué zonas ve cada usuario (Row-Level Security) |

### Por qué la diseñé así

Lo organicé como lo estaría en un edificio de verdad. Una zona tiene varios dispositivos, un dispositivo tiene varios sensores, y cada sensor genera muchas lecturas y puede disparar alarmas. Por eso las cuatro primeras tablas forman una cadena de Zonas a Dispositivos a Sensores, y de ahí salen Lecturas y Alarmas. Después, cada alarma puede tener una incidencia donde se anota qué la causó y cómo se arregló. Esas incidencias son las que luego quiero encontrar por significado cuando aparezca una alarma parecida.

En Lecturas guardo solo lo básico (sensor, fecha, valor y el JSON original del dispositivo) porque es la tabla que va a tener más de 500.000 filas, y quiero que sea ligera. De momento no tiene ningún índice aparte de la clave primaria, a propósito: así en la parte de optimización puedo medir cómo era la consulta antes y cómo mejora después de crearlo.

Documentos no está unida a ninguna otra tabla porque son manuales y procedimientos generales de los equipos, que valen para cualquier zona. UsuariosZona sirve para la seguridad por filas: dice qué zonas puede ver cada usuario.

Las columnas `Embedding` de Alarmas y Documentos son de tipo `VECTOR(768)`, porque `nomic-embed-text` genera vectores de 768 dimensiones. Ahora están vacías (aceptan `NULL`) y las relleno en la fase de embeddings.

### Restricciones

Para que no entren datos inválidos uso claves foráneas y restricciones `CHECK`. Por ejemplo:

- En Sensores, el valor mínimo normal tiene que ser menor que el máximo.
- En Incidencias, la fecha de cierre no puede ser anterior a la de apertura.
- La severidad de una alarma solo puede ser baja, media, alta o crítica, y el estado de un dispositivo o de una alarma solo puede tomar los valores previstos.
- El campo `PayloadJson` de Lecturas tiene que ser un JSON válido.
- Dentro de una zona no puede haber dos dispositivos con el mismo nombre, y dentro de un dispositivo tampoco dos sensores con el mismo nombre.

### Datos simulados

Los datos los genera [database/02_datos.sql](database/02_datos.sql), que se ejecuta después de crear las tablas. Tarda menos de un minuto en mi equipo y se puede repetir, porque borra los datos, reinicia los contadores y los vuelve a crear, así que los identificadores salen siempre iguales.

Hay 4 zonas, 8 dispositivos y 18 sensores. De cada sensor genero una lectura cada 5 minutos durante 100 días, del 20 de junio al 27 de septiembre de 2026, y eso da unas 518.000 lecturas. Cada valor sigue un ciclo diario (por ejemplo, más CO2 y más temperatura por la tarde en las oficinas) con una pequeña variación. Esa variación no sale de números aleatorios sino de una función hash, así que cualquiera que ejecute el script obtiene exactamente los mismos datos que yo.

![Filas de cada tabla](docs/images/01_recuento_filas.png)

Después meto 11 anomalías a propósito, cada una con su alarma y, casi todas, con su incidencia donde se cuenta la causa y la solución:

- Dos sensores de CO2 que se quedan en un valor fijo durante horas. El valor está dentro del rango normal, lo raro es que no se mueve, así que no se detecta mirando solo el rango.
- Dos subidas de temperatura en la sala de servidores, una por un fallo de refrigeración y otra tras un corte de luz.
- Humedad muy alta en el almacén por una fuga de agua.
- Caída de presión y de caudal en la bomba por perder el cebado.
- Consumo eléctrico doble en la sala de servidores de madrugada.
- Cinco horas sin lecturas en recepción por perder la conexión.
- Tres anomalías más cuyas alarmas siguen abiertas o en curso: temperatura baja en el almacén, temperatura alta en una oficina y consumo alto en la otra.

Las alarmas y sus incidencias las escribí con un lenguaje natural y con casos parecidos entre sí, para que más adelante la búsqueda por significado tenga algo que encontrar.


## T-SQL: función, vistas, procedimientos y trigger

Encima de las tablas he creado una función, dos vistas, dos procedimientos y un trigger. Los scripts están en [database/03_vistas_funcion.sql](database/03_vistas_funcion.sql) y [database/04_procedimientos_trigger.sql](database/04_procedimientos_trigger.sql).

### Función y vistas

La función `fn_EstadoValor` recibe un valor y el rango normal de un sensor y dice si está bajo, normal o alto. La uso dentro de la primera vista.

- `vw_UltimaLectura` enseña la última lectura de cada sensor con su zona y si está dentro de su rango. Es lo que miraría un operador para saber cómo está todo ahora mismo.
- `vw_AlarmasConIncidencia` junta cada alarma con su zona, su sensor y su incidencia, con los minutos que se tardó en resolver. No incluye la columna del embedding, porque no sirve para leerla. Las alarmas sin incidencia aparecen con valores vacíos.

![Las dos vistas](docs/images/01_vistas.png)

### Procedimientos

Los he llamado `usp_` y no `sp_`, porque `sp_` está reservado para los procedimientos del sistema y SQL Server los busca primero en la base de datos `master`.

- `usp_RegistrarAlarma` crea una alarma nueva y devuelve su identificador. Comprueba que el sensor existe y que la severidad es una de las permitidas, y si no, da un error con un mensaje claro.
- `usp_CerrarIncidencia` cierra la incidencia de una alarma. Si la alarma ya tenía una incidencia abierta la completa, y si no tenía, crea una ya cerrada.

Los dos usan parámetros y no construyen SQL con texto, así que no se pueden aprovechar para inyectar SQL.

![Errores controlados por el procedimiento](docs/images/01_procedimientos.png)

### Trigger

El trigger `trg_Incidencias_EstadoAlarma` actualiza solo el estado de la alarma cuando cambia su incidencia: si se abre una incidencia, la alarma pasa a "en curso", y si se cierra, pasa a "cerrada". Así no depende de que cada programa o usuario se acuerde de cambiar el estado. Está hecho para funcionar también cuando se tocan varias filas a la vez.

La prueba la hago dentro de una transacción que luego deshago, para no cambiar los datos. En la captura se ve cómo la misma alarma pasa de abierta a en curso y a cerrada:

![Ciclo de una alarma con el trigger](docs/images/01_trigger.png)

### Consultas avanzadas

Las consultas están en [database/05_consultas_avanzadas.sql](database/05_consultas_avanzadas.sql). Son solo de lectura y cada una responde a una pregunta del sistema.

**CTE.** Una expresión de tabla común sirve para resumir primero los datos y luego filtrar sobre el resumen.

- La primera resume las lecturas por sensor y día, y enseña los días en los que algún sensor se salió de su rango normal. Salen exactamente los días en que metí anomalías.
- La segunda busca sensores "planos": agrupa las lecturas por hora y se queda con las horas en las que las 12 lecturas valen lo mismo (desviación cero). Encuentra los dos sensores de CO2 que se quedaron fijos, algo que mirando solo el rango no se vería, porque su valor era normal.

![Consultas con CTE](docs/images/01_cte.png)

**Funciones de ventana.** Permiten calcular sobre un grupo de filas sin juntarlas en una sola.

- La primera da a cada alarma su puesto dentro de su zona según lo que tardó en resolverse (`RANK`) y cuántas alarmas lleva acumuladas la zona. Las alarmas sin resolver quedan en último lugar.
- La segunda calcula la media móvil de la última hora de la temperatura de la sala de servidores el día del fallo de refrigeración. Se ve cómo la media sube con retraso respecto al valor real cuando la temperatura salta de 22 a 32 grados.

![Funciones de ventana](docs/images/01_window.png)

**JSON.** Cada lectura guarda el mensaje original del dispositivo, y se puede consultar sin haberlo separado en columnas.

- `JSON_VALUE` saca la batería y la señal de cada mensaje, y con eso calculo la batería media y la señal mínima de cada dispositivo.
- `OPENJSON` abre un mensaje y lo convierte en una fila por campo.

![Consultas con JSON](docs/images/01_json.png)

### Pruebas

[tests/tests.sql](tests/tests.sql) comprueba de una vez que todo lo anterior está en su sitio: las 8 tablas, las columnas de tipo vector, la función, las vistas, los procedimientos y el trigger, que hay más de 500.000 lecturas, que el `CHECK` rechaza un rango al revés, que el procedimiento da error con un sensor que no existe y que el trigger cierra la alarma. Al final sale una tabla con OK o FALLO por cada prueba. Las que tocan datos se hacen dentro de una transacción que se deshace, y lo iré ampliando con cada fase.

![Resultado de las pruebas](docs/images/01_tests.png)


## Seguridad

La seguridad está en [database/06_seguridad.sql](database/06_seguridad.sql) y sus pruebas en [database/07_seguridad_pruebas.sql](database/07_seguridad_pruebas.sql). La idea es que cada persona vea solo lo que necesita para su trabajo.

### Quién es quién

Hay dos roles y cuatro usuarios. Los usuarios los he creado sin login (`CREATE USER ... WITHOUT LOGIN`), así que no se pueden usar para conectarse a SQL Server, solo para probar con `EXECUTE AS` desde mi sesión. De esa forma no hay ninguna contraseña en el proyecto.

| Usuario | Rol | Zonas que ve | Emails de contacto | Tabla Lecturas |
| --- | --- | --- | --- | --- |
| admin_scada | rol_admin_scada | Todas | Completos | Acceso total |
| tecnico_cpd | rol_tecnico | Sala de servidores | Enmascarados | Denegado, solo con la vista |
| tecnico_oficinas | rol_tecnico | Recepcion y Oficinas | Enmascarados | Denegado, solo con la vista |
| tecnico_almacen | rol_tecnico | Almacen | Enmascarados | Denegado, solo con la vista |

Qué zonas tiene cada técnico lo dice la tabla `UsuariosZona`. Si mañana hay que darle otra zona a un técnico, se añade una fila y no hay que tocar ningún permiso.

### Seguridad por filas

Con Row-Level Security, SQL Server filtra las filas según quién consulta, sin que la consulta tenga que cambiar. Lo he aplicado a Zonas, Dispositivos, Sensores, Alarmas e Incidencias, y además hay un bloqueo para que un técnico no pueda crear alarmas ni incidencias en una zona que no es la suya. El administrador y yo (como `db_owner`) lo vemos todo.

La misma consulta con los dos usuarios. El administrador ve las 4 zonas y las 11 alarmas:

![RLS con el administrador](docs/images/02_rls_admin.png)

Y el técnico de la sala de servidores ve solo su zona y sus 3 alarmas:

![RLS con el técnico](docs/images/02_rls_tecnico.png)

A la tabla Lecturas, que tiene más de 500.000 filas, no le he puesto seguridad por filas, para no añadir una comprobación a cada fila en cada consulta. En su lugar, el técnico no puede leerla directamente (`DENY`) y consulta las lecturas con la vista `vw_LecturasVisibles`, que hereda la seguridad de la tabla Sensores y por eso solo le deja ver las de sus sensores. Es una decisión que tomé por el rendimiento, y a cambio la seguridad de esta tabla depende de que nadie le dé permisos directos.

### Enmascarado de datos

El email de contacto de cada zona está enmascarado con Dynamic Data Masking. El administrador, que tiene el permiso `UNMASK`, lo ve completo, y los técnicos lo ven tapado (solo se ve la primera letra):

![Enmascarado del email](docs/images/02_ddm.png)

### Permisos mínimos

El técnico tiene solo lo necesario para su trabajo: puede leer las alarmas, incidencias, sensores y manuales de sus zonas, y registrar o cerrar alarmas con los dos procedimientos. No puede borrar alarmas ni incidencias, ni modificar zonas, dispositivos o sensores, ni tocar la tabla Lecturas. Cada uno de esos permisos está dado con `GRANT` o quitado con `DENY` en el script.

Probé qué pasa cuando el técnico de la sala de servidores intenta lo que no debe, dentro de una transacción que se deshace:

![Intentos denegados](docs/images/02_deny.png)

El error 229 es "permiso denegado". Crear una alarma en una zona ajena da el error 50001 ("el sensor no existe"), porque el técnico ni siquiera ve los sensores de otras zonas.

## Cómo voy

- [x] Comprobar que SQL Server puede generar embeddings con Ollama
- [x] Diseño de la base de datos y T-SQL
- [ ] Seguridad (Row-Level Security, Dynamic Data Masking) y optimización de una consulta
- [ ] Embeddings y búsqueda semántica
- [ ] RAG con modelo local
- [ ] Documentar el uso de IA durante el desarrollo

Las veces que he usado IA y cómo comprobé lo que me daba las voy apuntando en [docs/uso-de-ia.md](docs/uso-de-ia.md).

<!-- Cambia [ ] por [x] cuando termines cada punto. Al acabar el proyecto puedes borrar esta lista o dejarla marcada. -->

## Cómo probarlo

De momento solo está la comprobación del entorno:

1. Instalar Ollama y montar el proxy siguiendo [setup/ollama-https-proxy.md](setup/ollama-https-proxy.md).
2. Ejecutar [setup/00_verificar_entorno.sql](setup/00_verificar_entorno.sql) en SSMS, bloque a bloque.

Los certificados no están en el repositorio: cada uno tiene que generar los suyos con mkcert.

<!-- FASE 5: sustituye esto por la instalación completa paso a paso: el orden de los scripts de database/ y ai/, qué hay que tener en marcha y cuánto tarda. Hazlo después de la prueba de reproducibilidad, clonando el repo en otra carpeta, para que sea el orden real. -->

<!--
SECCIONES QUE VAS A AÑADIR AL README
Cuando llegues a cada fase, copia el título, escribe la sección con tus palabras y borra el comentario correspondiente. Todas van debajo de "Cómo probarlo" o donde te parezca natural. Las guías de cada paso están en el documento de la guía.

## Optimización de una consulta (Fase 2)
Qué consulta elegiste y por qué, cómo era el plan antes (tipo de acceso, logical reads, tiempo), qué índice creaste y cómo quedó después. Explica por qué mejora, o por qué no mejora tanto. Capturas: 02_plan_antes.png y 02_plan_despues.png.

## Embeddings (Fase 3)
El enunciado pide cinco cosas: qué modelo usas, qué columnas se convierten en vector, qué dimensión tiene, cómo se generan y cómo se guardan en SQL Server. Cuéntalo con tus palabras. Captura: 03_embeddings.png.

## Búsqueda semántica (Fase 3)
Una tabla con las cinco preguntas que probaste, qué salió primero y si acertó, incluidos los fallos. Y por qué usas la métrica coseno, que el enunciado exige justificar. Capturas: 03_ranking_1.png y siguientes.

## RAG (Fase 4)
Qué modelo de lenguaje elegiste y por qué, cómo funciona el flujo (pregunta, documentos recuperados, contexto, respuesta) y la diferencia entre usar el modelo solo y usar RAG, con el ejemplo de la misma pregunta de las dos formas. Capturas: 04_rag_salida.png, 04_sin_rag.png y 04_con_rag.png.

## Uso de IA durante el desarrollo
Un resumen corto de para qué usaste IA y un enlace a docs/uso-de-ia.md, donde van las fichas con prompt, respuesta, qué aceptaste, qué corregiste y cómo lo verificaste.

## Ejemplos (Fase 5)
Dos o tres consultas con su resultado, las que mejor enseñen el proyecto.

## Conclusiones (Fase 5)
Qué has aprendido, qué problemas tuviste, cómo los resolviste y qué mejorarías.
-->
