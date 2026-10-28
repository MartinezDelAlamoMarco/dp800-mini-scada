# Uso de IA durante el desarrollo

Aquí dejo cada vez que he usado IA de forma significativa en el proyecto: qué pregunté, qué me respondió, qué acepté, qué tuve que corregir y cómo comprobé que estaba bien. Lo voy rellenando según avanzo, no al final.

La herramienta que uso es Claude, con una suscripción Pro. No me fío de nada que no haya ejecutado yo en mi equipo, así que cada ficha termina con la prueba que hice.

## Para qué he usado la IA

- Pedirle ayuda con el código: borradores de los scripts de T-SQL (tablas, datos simulados, vistas, procedimientos, trigger, seguridad y el índice), que luego he ejecutado, probado y corregido.
- Resolver dudas de cómo funcionan las cosas de SQL Server 2025: llamadas REST, seguridad por filas, enmascarado de datos, planes de ejecución, vectores.
- Montar el entorno (Ollama, nginx, certificados) y entender los errores que salían.
- Revisar resultados y ayudarme a documentar el proyecto.

Las decisiones de qué hacer y la comprobación de que funciona las he hecho yo en mi equipo, y cada ficha explica qué acepté y qué tuve que corregir.

## 1. Llamada REST desde SQL Server a Ollama

- Fase y objetivo: Fase 0, comprobar que SQL Server llega a Ollama a través del proxy.
- Herramienta: Claude.

Mis dudas (al ejecutar el script no supe interpretar el resultado):

```
¿Cómo sé que la llamada a Ollama se ha ejecutado bien?
Solo me pone "Los comandos se han completado correctamente" y no sale el code 200, ¿qué estoy haciendo mal?
```

Lo que respondió, en resumen: me había dado el script de comprobación con `sp_invoke_external_rest_endpoint` suponiendo que devolvía la respuesta como una tabla. Lo corrigió al ver mi resultado y me explicó que la respuesta sale por el parámetro `@response`, que hay que declararlo como `OUTPUT` y sacarlo con un `SELECT`.

Qué acepté:

- La explicación del parámetro `@response OUTPUT` y el `SELECT` para ver el resultado.
- Mirar el código de retorno (0 si va bien) junto con el `"code":200` de la respuesta.

Qué tuve que corregir y por qué:

- El primer script que me dio no mostraba nada, y era un fallo de la IA, no mío. Lo noté porque no aparecía ninguna tabla de resultados, y a partir de ahí el script quedó corregido en `setup/00_verificar_entorno.sql`.

Cómo verifiqué que era correcto:

- Consulta o prueba ejecutada: el bloque de llamada directa al proxy de `setup/00_verificar_entorno.sql`.
- Resultado: `CodigoRetorno` 0 y la respuesta empieza por `{"response":{"status":{"http":{"code":200`.
- Captura: `docs/images/00_llamada_rest.png`

## 2. Pasar el JSON a curl desde PowerShell

- Fase y objetivo: Fase 0, probar Ollama y el proxy con curl.
- Herramienta: Claude.

Mis dudas (el curl que probé no funcionaba):

```
¿Por qué me falla el curl contra Ollama desde PowerShell?
¿Cómo tengo que pasarle el JSON del modelo de embedding para que funcione?
```

Lo que respondió, en resumen: el comando con el JSON en la misma línea que me había dado no funcionaba en PowerShell porque estropea las comillas dobles. Propuso guardar el cuerpo en un `body.json` y usar `-d "@body.json"`.

Qué acepté:

- Usar un archivo `body.json` en lugar de escribir el JSON en la línea de comandos.

Qué tuve que corregir y por qué:

- Me falló una vez con "Failed to open body.json" porque el archivo no estaba creado en `C:\nginx` y yo estaba en esa carpeta. Hubo que crearlo primero con `Out-File`, y eso quedó añadido en `setup/ollama-https-proxy.md`.

Cómo verifiqué que era correcto:

- Consulta o prueba ejecutada: el curl contra `https://localhost:11435/api/embed` con `--ssl-no-revoke`.
- Resultado: devuelve el vector de `nomic-embed-text` con los números.
- Captura: `docs/images/00_curl_proxy.png`

## 3. Diseño de las tablas y datos simulados

- Fase y objetivo: Fase 1, crear las 8 tablas de la base de datos y cargarlas con datos de prueba.
- Herramienta: Claude.

Lo que le pedí y mis dudas:

```
¿Cómo diseño las 8 tablas del Mini-SCADA (zonas, dispositivos, sensores, lecturas, alarmas, incidencias, documentos y usuarios) con sus claves y restricciones?
¿Puedes ayudarme a escribir el script de datos simulados con más de 500.000 lecturas, alarmas con anomalías y sus incidencias?
```

Lo que respondió, en resumen: el script `database/01_tablas.sql` con las 8 tablas, claves foráneas y restricciones `CHECK`, y el script `database/02_datos.sql`, que genera las lecturas con un ciclo diario y una variación repetible, y mete 11 anomalías con sus alarmas e incidencias.

Qué acepté:

- El diseño de las 8 tablas tal como estaba previsto en la propuesta.
- Dejar Lecturas sin índice a propósito, para medir después la mejora en la parte de optimización.
- Generar la variación con una función hash y no con números aleatorios, para que los datos sean siempre los mismos.

Qué tuve que corregir y por qué:

- El script de tablas no necesitó cambios. El de datos se ejecutó sin errores, pero tuvo dos fallos que solo vi después, al hacer las consultas avanzadas:
  - El "ruido" de las lecturas casi no variaba de una lectura a la siguiente, porque la función que usó (`CHECKSUM`) da valores muy parecidos para números seguidos. Lo noté cuando la consulta de sensores planos marcó 57 horas de la presión de la bomba, que no eran una anomalía que yo hubiera metido, y en la media móvil, donde el ruido se mantenía casi igual de una hora a otra. También hacía que la batería de los mensajes JSON subiera de uno en uno. Lo sustituí por un hash MD5 del sensor y del número de lectura.
  - Al volver a ejecutar el script los identificadores no empezaban en 1 sino donde se quedó la vez anterior, así que quien lo ejecutara desde cero vería números distintos a los de mis capturas. Hice que el script reinicie los contadores al empezar.
  Después de los dos cambios repetí el script, las pruebas y las capturas.

Cómo verifiqué que era correcto:

- Consulta o prueba ejecutada: las consultas de comprobación del final de `02_datos.sql`.
- Resultado: 518.220 lecturas, 18 sensores, 11 alarmas y 9 incidencias. Las lecturas fuera de rango por sensor coinciden con las anomalías que se meten: 108 en la temperatura de la sala de servidores, que son 9 horas en total, o 60 en la humedad del almacén, que son 5 horas.
- Captura: `docs/images/01_recuento_filas.png`

## 4. Función, vistas, procedimientos y trigger

- Fase y objetivo: Fase 1, la parte de T-SQL: una función, dos vistas, dos procedimientos y un trigger.
- Herramienta: Claude.

Lo que le pedí y mis dudas:

```
¿Puedes ayudarme con la parte de T-SQL: una función, dos vistas, dos procedimientos y un trigger?
¿Cómo hago que cambiar el estado de una alarma lo haga el trigger y cómo pruebo los procedimientos sin ensuciar los datos?
```

Lo que respondió, en resumen: los scripts `database/03_vistas_funcion.sql` y `database/04_procedimientos_trigger.sql`, con pruebas al final de cada uno. Las pruebas de los procedimientos y el trigger se hacen dentro de una transacción que se deshace.

Qué acepté:

- Llamar a los procedimientos `usp_` y no `sp_`.
- Que el cambio de estado de la alarma lo haga el trigger y no el procedimiento, para que funcione también si alguien toca la tabla directamente.
- Probarlo todo con `ROLLBACK` para no ensuciar los datos.

Qué tuve que corregir y por qué:

- Nada: los dos scripts se ejecutaron sin errores y las pruebas dieron lo esperado.

Cómo verifiqué que era correcto:

- Consulta o prueba ejecutada: las pruebas del final de cada script.
- Resultado: la vista de últimas lecturas tiene 18 filas y la de alarmas 11, con incidencia en 9. Los dos errores controlados dan los números 50001 y 50002, y el ciclo de una alarma pasa por abierta, en curso y cerrada.
- Capturas: `docs/images/01_vistas.png`, `docs/images/01_procedimientos.png` y `docs/images/01_trigger.png`

## 5. Consultas avanzadas y pruebas

- Fase y objetivo: Fase 1, consultas con CTE, funciones de ventana y JSON, y un archivo de pruebas automáticas.
- Herramienta: Claude.

Lo que le pedí y mis dudas:

```
¿Puedes ayudarme con consultas avanzadas (CTE, funciones de ventana y JSON) sobre las lecturas?
¿Cómo encuentro un sensor que se ha quedado "plano" aunque su valor sea normal?
¿Cómo monto un archivo de pruebas automáticas para repetirlas siempre?
```

Lo que respondió, en resumen: el script `database/05_consultas_avanzadas.sql` con dos consultas CTE, dos de ventana y dos de JSON, y el archivo `tests/tests.sql` con 9 pruebas.

Qué acepté:

- Buscar los sensores "planos" agrupando por hora y mirando la desviación, porque es la forma de encontrar un sensor que no se mueve aunque su valor sea normal.
- Hacer las pruebas dentro de una transacción que se deshace.

Qué tuve que corregir y por qué:

- Nada en las consultas en sí. Pero esta consulta de sensores planos fue la que enseñó el fallo del ruido de los datos que cuento en la ficha 3, así que la corrección fue en el script de datos.

Cómo verifiqué que era correcto:

- Consulta o prueba ejecutada: las consultas del script y el archivo `tests/tests.sql`.
- Resultado: la consulta de sensores planos encuentra solo los dos CO2 que dejé fijos a propósito, 12 horas en la oficina 2 y 6 en la oficina 1. Los días con valores fuera de rango son los de las anomalías, y las 9 pruebas dan OK.
- Capturas: `docs/images/01_cte.png`, `docs/images/01_window.png`, `docs/images/01_json.png` y `docs/images/01_tests.png`

## 6. Seguridad: roles, seguridad por filas, enmascarado y permisos

- Fase y objetivo: Fase 2, que cada técnico vea solo su zona, ocultar el email de contacto y dar los permisos mínimos.
- Herramienta: Claude.

Lo que le pedí y mis dudas:

```
¿Cómo hago que cada técnico vea solo las alarmas y lecturas de su zona?
¿Cómo oculto el email de contacto y doy a cada rol solo los permisos mínimos?
¿Cómo pruebo todo esto sin crear usuarios con contraseña?
```

Lo que respondió, en resumen: el script `database/06_seguridad.sql` con dos roles, cuatro usuarios sin login, una política de seguridad por filas, el enmascarado del email y los permisos con `GRANT` y `DENY`, y el script `database/07_seguridad_pruebas.sql` con las pruebas usando `EXECUTE AS`. También cambió `01_tablas.sql` para que se pueda volver a ejecutar desde cero cuando ya existe la política.

Qué acepté:

- Crear los usuarios sin login, para no tener contraseñas en el proyecto.
- No poner seguridad por filas a la tabla Lecturas por el tamaño, y proteger su acceso con `DENY` y una vista que hereda la seguridad de Sensores.
- Dejar pasar siempre al administrador y a `db_owner` en la política, para que yo no me quede sin ver datos.
- Hacer las pruebas que intentan modificar datos dentro de una transacción que se deshace.

Qué tuve que corregir y por qué:

- Nada: los dos scripts se ejecutaron sin errores y las pruebas dieron el resultado esperado.

Cómo verifiqué que era correcto:

- Consulta o prueba ejecutada: las tres pruebas de `07_seguridad_pruebas.sql`.
- Resultado: el administrador ve 4 zonas y 11 alarmas, y el técnico de la sala de servidores 1 zona y 3 alarmas. El email sale tapado para el técnico. Leer Lecturas, borrar alarmas y modificar zonas dan el error 229, la vista de lecturas da 115.200 filas de su zona, y crear una alarma en otra zona da el error 50001.
- Capturas: `docs/images/02_rls_admin.png`, `docs/images/02_rls_tecnico.png`, `docs/images/02_ddm.png` y `docs/images/02_deny.png`

## 7. Optimización de una consulta con un índice

- Fase y objetivo: Fase 2, elegir una consulta sobre Lecturas, medirla sin índice, crear un índice compuesto y volver a medir.
- Herramienta: Claude.

Lo que le pedí y mis dudas:

```
¿Qué consulta de Lecturas me conviene optimizar y cómo mido su coste antes y después de crear un índice?
¿Puedes encargarte tú de ejecutar el script en mi SSMS y hacer las capturas del plan y de las lecturas?
```

Lo que respondió, en resumen: el script `database/08_optimizacion.sql`, con la media de CO2 de la oficina 1 durante una semana, un bloque para medir sin índice, otro que crea el índice `IX_Lecturas_Sensor_Fecha (SensorId, FechaHora) INCLUDE (Valor)` y otro para medir con índice. Después ejecutó el script en mi SSMS y guardó las capturas del plan y de las lecturas.

Qué acepté:

- Elegir una consulta por sensor y rango de fechas, que es la que más se hace en un sistema de este tipo.
- El orden de las columnas del índice (primero el sensor, que es igualdad, y luego la fecha, que es rango) y poner `Valor` en `INCLUDE`.
- Vaciar la caché antes de cada medición y repetir la consulta con la caché caliente.

Qué tuve que corregir y por qué:

- La primera versión del script guardaba las lecturas en una tabla temporal leyendo `sys.dm_exec_requests`. Al comparar, los números no coincidían con los de `SET STATISTICS IO` en el caso sin índice, así que lo cambió para usar `SET STATISTICS IO, TIME ON`, que es lo que se ve directamente en SSMS.
- Con el plan de ejecución real activado, los tiempos salían inflados (más de 1 segundo para una consulta de 13 lecturas). Los tiempos de la tabla los midió con el plan desactivado y el plan lo sacó aparte.

Cómo verifiqué que era correcto:

- Consulta o prueba ejecutada: el script `08_optimizacion.sql`, bloque a bloque, con el índice borrado antes de cada medición sin índice.
- Resultado: sin índice, `Clustered Index Scan`, 15.771 lecturas lógicas y 241 ms con la caché fría. Con índice, `Index Seek`, 13 lecturas lógicas y 4 ms. La media sale igual en las dos ocasiones (619,98 ppm sobre 2.016 lecturas), así que el índice no cambia el resultado. El índice ocupa 16,7 MB, según la consulta de tamaños del último bloque del script.
- Capturas: `docs/images/02_plan_antes.png`, `docs/images/02_lecturas_antes.png`, `docs/images/02_plan_despues.png` y `docs/images/02_lecturas_despues.png`

## 8. Embeddings y búsqueda semántica

- Fase y objetivo: Fase 3, escribir los manuales, generar los embeddings dentro de SQL Server y buscar por significado con `VECTOR_DISTANCE`.
- Herramienta: Claude.

Lo que le pedí y mis dudas:

```
¿Puedes escribirme diez manuales y procedimientos cortos con los que probar la búsqueda, sobre lo que haría un técnico ante cada tipo de alarma?
¿Cómo relleno las columnas VECTOR(768) de Alarmas y Documentos desde SQL Server con el modelo de Ollama?
¿Cómo busco los documentos más parecidos a una pregunta con VECTOR_DISTANCE, y por qué se usa la distancia coseno?
```

Lo que respondió, en resumen: los scripts `database/09_documentos.sql` (diez documentos de tipo manual, procedimiento y guía, relacionados con las alarmas de los datos de prueba), `database/10_embeddings.sql` (un `UPDATE` con `AI_GENERATE_EMBEDDINGS` que solo rellena las filas sin embedding) y `database/11_busqueda.sql` (dos procedimientos de búsqueda y una tabla resumen con las cinco preguntas).

Qué acepté:

- Concatenar título y contenido de cada documento antes de generar el embedding.
- Hacer la búsqueda en un procedimiento (`usp_BuscarDocumentos`), para reutilizarlo después en el RAG.
- Usar la distancia coseno y no tener índice vectorial, porque con diez documentos la búsqueda exacta es instantánea.
- Escribir las preguntas de prueba como las diría un técnico y no copiando frases de los manuales, para que la prueba no sea trampa.

Qué tuve que corregir y por qué:

- La tabla resumen de las cinco preguntas salió con una sola fila. Era un fallo del script que me dio: la columna de orden era un `IDENTITY` y, al limpiar la tabla temporal con `DELETE` en cada vuelta del bucle, no se reiniciaba y las posiciones de las preguntas 2 a 5 salían como 3, 4, 5... en lugar de 1 y 2, así que el `JOIN` no las encontraba. Lo vi porque solo aparecía la pregunta 1. Se cambió `DELETE` por `TRUNCATE TABLE` y se repitió el script.

Cómo verifiqué que era correcto:

- Consulta o prueba ejecutada: `10_embeddings.sql` (conteo de filas con embedding y sus dimensiones) y `11_busqueda.sql`.
- Resultado: 11 alarmas y 10 documentos con embedding, de 768 dimensiones. Las cinco preguntas devuelven como primer resultado el documento esperado, con distancias entre 0,12 y 0,28. En una de ellas (corte de luz y aire de la sala de servidores) el manual de refrigeración queda segundo, detrás del procedimiento de corte de luz, y lo he dejado dicho en el README.
- Capturas: `docs/images/03_embeddings.png` y `docs/images/03_busqueda.png`

## 9. RAG con un modelo local

- Fase y objetivo: Fase 4, hacer que un modelo de lenguaje local conteste usando los documentos que encuentra la búsqueda semántica, y comparar con las respuestas sin RAG.
- Herramienta: Claude.

Lo que le pedí y mis dudas:

```
¿Qué modelo de lenguaje pequeño puedo usar en local con Ollama para el RAG?
¿Puedo usar el modelo externo de SQL Server para generar texto, o solo sirve para embeddings?
¿Cómo escribo un procedimiento que busque los documentos, monte el prompt y llame al modelo desde T-SQL?
¿Cómo consigo que el modelo diga que no sabe algo cuando no está en los manuales?
```

Lo que respondió, en resumen: SQL Server 2025 solo admite modelos externos de tipo embeddings, así que la generación se hace llamando a `/api/chat` de Ollama con `sp_invoke_external_rest_endpoint`. Me dio el script `database/12_rag.sql`, con el procedimiento `usp_PreguntarRAG` (recupera dos documentos con `VECTOR_DISTANCE`, monta el prompt, llama al modelo y lee la respuesta del JSON) y una comparación de cuatro preguntas sin y con RAG. También me propuso el modelo Llama 3.2 3B y subir el tiempo de espera de nginx.

Qué acepté:

- Un modelo pequeño (3B, cuantizado) para que funcione en mi portátil sin GPU.
- Temperatura 0 y `seed` fija para que las respuestas se parezcan entre ejecuciones.
- Pedir al modelo que use solo los documentos y que, si no está la respuesta, diga exactamente "No lo encuentro en los manuales."
- Incluir una cuarta pregunta (el incendio en la sala de servidores) que no está en ningún manual, para ver qué pasa cuando no hay información.

Qué tuve que corregir y por qué:

- `ollama pull llama3.2:3b` fallaba por un error de red (no conectaba con el servidor de descarga). Lo solucioné bajando el mismo modelo desde Hugging Face con `ollama pull hf.co/bartowski/Llama-3.2-3B-Instruct-GGUF:Q4_K_M` y cambiando el nombre del modelo en el script.
- La llamada al modelo se cortaba por tiempo: nginx cierra la conexión a los 60 segundos y generar la respuesta tarda más. Añadí `proxy_read_timeout 300s` en `setup/nginx.conf`, copié el archivo a `C:\nginx\conf` y recargué nginx.
- Al sacar el resultado dio el error 5373 ("todos los parámetros de entrada deben ser del mismo tipo") en `GENERATE_SERIES`, porque `LEN` devuelve `BIGINT` y el otro argumento era `INT`. Se arregló con `CAST(... AS INT)` en los dos.
- Los cortes de las respuestas en líneas de 110 caracteres parten alguna palabra por la mitad. Lo dejé así porque solo es para que quepa en la captura.

Cómo verifiqué que era correcto:

- Consulta o prueba ejecutada: `12_rag.sql` entero en SSMS, mirando las respuestas de las cuatro preguntas sin y con RAG y comparándolas con el texto de los documentos de `09_documentos.sql`.
- Resultado: con RAG, la respuesta sobre la severidad alta dice "máximo de 1 hora" (como la guía), la de calibración da seis meses, 20 grados, 75 % de humedad y el ajuste del offset (como el manual), y la de la bomba coincide con el manual. Sin RAG el modelo se inventa "15-30 minutos" y "cada 3 meses". En la pregunta del incendio, con RAG responde "No lo encuentro en los manuales." y sin RAG da consejos inventados. El script entero tardó 1 minuto y 1 segundo.
- Capturas: `docs/images/04_comparacion_1.png` y `docs/images/04_comparacion_2.png`

## 10. Cierre: pruebas, diagrama, informe y presentación

- Fase y objetivo: Fase 5, ampliar las pruebas, hacer el diagrama de arquitectura y la demo del RAG, comprobar que se puede reproducir todo desde cero y preparar el informe y la presentación.
- Herramienta: Claude.

Lo que le pedí y mis dudas:

```
El enunciado pide ver la pregunta, los documentos recuperados, el contexto y la respuesta del RAG. ¿Cómo lo enseño en una sola consulta?
¿Cómo amplío tests.sql con pruebas de los embeddings y de la búsqueda semántica?
¿Cómo compruebo que el proyecto se puede reproducir desde cero, borrando la base de datos y ejecutando todos los scripts en orden?
¿Qué diagrama de arquitectura incluyo en el README y en el informe?
¿Cómo monto el informe de 5 a 10 páginas y la presentación de 8 diapositivas con lo que ya tengo?
```

Lo que respondió, en resumen: el script `database/13_rag_demo.sql` (una tabla con la pregunta, los dos documentos recuperados con su distancia, el contexto y la respuesta), cuatro pruebas nuevas para `tests/tests.sql`, un script en modo SQLCMD para borrar `MiniScada` y lanzar todos los scripts en orden con la hora de cada paso, el diagrama `docs/images/arquitectura.png`, el informe `docs/informe.pdf` y la presentación `presentation/dp800-project.pptx`.

Qué acepté:

- Hacer la demo del RAG con una sola pregunta y mostrarla por pasos, además de la comparación de las cuatro preguntas que ya tenía.
- Que las pruebas de los embeddings dependan de que Ollama esté en marcha, y dejarlo avisado en el encabezado de `tests.sql`.
- Medir el tiempo de la reconstrucción completa y ponerlo en el README.
- Seguir el guion de la presentación que tenía, con la demo en tres partes (RAG, seguridad y optimización) y una captura de respaldo.

Qué tuve que corregir y por qué:

- El primer diagrama, hecho con Mermaid, salió desordenado y la etiqueta de HTTPS tapaba una flecha. Se rehízo a mano con posiciones fijas.
- El script de reconstrucción con `:setvar` para la ruta del repositorio fallaba con "no se encuentra el directorio" (la ruta tiene espacios). Se arregló escribiendo la ruta completa en cada línea `:r`.
- El informe salió con el título del apartado 10 solo al final de una página, y en el texto del enmascarado puse un formato de email que no era el real (`xXXX@XXXX.com`, cuando en la captura sale `rXXX@XXXX.com`). Se corrigió.
- En la presentación los títulos salieron centrados y la captura del RAG pequeña. Se alinearon a la izquierda y se agrandó la captura.

Cómo verifiqué que era correcto:

- Consulta o prueba ejecutada: `13_rag_demo.sql`, `tests/tests.sql` y la reconstrucción completa (borrar `MiniScada` y ejecutar `00_verificar_entorno` y los scripts del 01 al 12 y las pruebas).
- Resultado: la demo recupera el procedimiento del sensor de CO2 plano (distancia 0,1309) y el manual de calibración (0,3137) y responde con los pasos del primero. Las 18 pruebas dan 18 correctas y 0 fallidas, y la reconstrucción entera salió sin errores en 2 minutos y 6 segundos.
- Capturas: `docs/images/04_rag_demo.png` y `docs/images/01_tests.png`
