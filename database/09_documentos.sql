-- Mini-SCADA: manuales y procedimientos que luego se usan para la busqueda
-- semantica y el RAG. Son documentos cortos inventados para el proyecto, con el
-- tipo de cosas que tendria a mano un tecnico: que hacer ante cada alarma.
--
-- Se puede ejecutar varias veces: vacia la tabla y la vuelve a cargar.
-- Los embeddings se generan despues, en 10_embeddings.sql.

USE MiniScada;
GO

DELETE FROM dbo.Documentos;
IF EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('dbo.Documentos') AND last_value IS NOT NULL)
    DBCC CHECKIDENT ('dbo.Documentos', RESEED, 0);
GO

INSERT dbo.Documentos (Titulo, Tipo, Contenido)
VALUES
(N'Procedimiento: sensor de CO2 con lecturas planas', 'procedimiento',
 N'Cuando un sensor de CO2 muestra siempre el mismo valor durante varias horas, aunque la sala se llene o se vacie, lo normal es que este descalibrado o sucio y no que el aire sea constante. Pasos: 1) Comparar con el otro sensor de CO2 de la misma planta. 2) Revisar la entrada de aire del sensor y quitar el polvo con aire comprimido. 3) Hacer la calibracion a aire exterior (400 ppm) siguiendo el manual del fabricante. 4) Si tras calibrar el valor sigue sin moverse, sustituir el sensor. Dejar anotado en la incidencia la causa y el numero de serie del sensor nuevo.'),
(N'Manual: refrigeracion de la sala de servidores', 'manual',
 N'La sala de servidores debe mantenerse entre 18 y 27 grados. Si la temperatura supera los 27 grados y sigue subiendo, comprobar primero si el aire acondicionado esta encendido y si el equipo de refrigeracion muestra algun error. Despues de un corte de luz, el aire acondicionado puede quedarse apagado y no volver a arrancar solo: hay que rearmarlo desde el panel. Si hay rejillas o filtros sucios, limpiarlos. Con mas de 30 grados, avisar al responsable de sistemas y empezar a apagar los equipos no criticos para evitar danos. Dejar la puerta cerrada para no perder el aire frio.'),
(N'Guia: humedad alta en el almacen', 'guia',
 N'Una humedad por encima del 75 por ciento en el almacen puede estropear el material y oxidar los equipos. Pasos: 1) Buscar una posible fuga de agua cerca del sensor, en tuberias, cubierta o desagues. 2) Revisar que la puerta del muelle no este abierta con lluvia. 3) Encender el deshumidificador portatil y comprobar que su deposito no este lleno. 4) Si la humedad sube del 90 por ciento, mover el material sensible y avisar al mantenimiento del edificio. Despues de arreglar la causa, vigilar el sensor durante 24 horas.'),
(N'Manual: bomba de agua del almacen, caida de presion', 'manual',
 N'En funcionamiento normal la bomba trabaja entre 1,5 y 4 bar. Si la presion cae por debajo de 1 bar y casi no hay caudal, parar la bomba para no quemar el motor. Causas habituales: perdida del cebado por aire en la tuberia, filtro de entrada obstruido, valvula de aspiracion cerrada o junta del eje desgastada. Pasos: 1) Cerrar la valvula de salida y purgar el aire. 2) Limpiar el filtro de entrada. 3) Cebar la bomba llenandola de agua. 4) Arrancar y comprobar que la presion sube a su valor normal. Si hay ruido de rodamientos o fuga por el eje, sustituir la junta y avisar al tecnico de mantenimiento.'),
(N'Procedimiento: nodo que no envia lecturas', 'procedimiento',
 N'Si un nodo ESP32 deja de enviar lecturas, primero comprobar que tiene alimentacion y que el led de estado parpadea. Pasos: 1) Reiniciar el nodo desconectando y volviendo a conectar la alimentacion. 2) Comprobar que el punto de acceso wifi funciona y que la senal es suficiente (rssi mejor que -75). 3) Revisar que el broker MQTT esta en marcha. 4) Si el nodo no arranca, reflashear el firmware por USB. 5) Si el problema se repite, sustituir la fuente de alimentacion. Mientras el nodo este caido, marcar sus sensores como sin datos para que no salten falsas alarmas.'),
(N'Guia: consumo electrico anormal', 'guia',
 N'Un consumo que duplica el valor habitual indica que hay equipos funcionando que no deberian o que algo esta fallando. En un rack, mirar si hay un servidor atascado al cien por cien de CPU, ventiladores al maximo o una fuente de alimentacion defectuosa. En una oficina, comprobar calefaccion, aire acondicionado y equipos que se hayan quedado encendidos. Pasos: 1) Identificar que circuito sube con el cuadro electrico. 2) Desconectar los equipos no necesarios. 3) Medir con pinza amperimetrica. 4) Si el consumo no baja, avisar al electricista. Anotar la hora en que empezo para cruzarla con otros eventos.'),
(N'Procedimiento: temperatura baja en el almacen', 'procedimiento',
 N'Cuando la temperatura del almacen baja de 8 grados, normalmente es porque la puerta del muelle se ha quedado abierta o porque falla la calefaccion. Pasos: 1) Ir al muelle y cerrar la puerta. 2) Revisar el cierre automatico y la goma del borde. 3) Comprobar que la calefaccion esta en marcha. 4) Proteger los materiales sensibles al frio. Si la temperatura no se recupera en una hora, abrir una incidencia y avisar a mantenimiento. Cerrar la alarma cuando se mantenga por encima de 10 grados.'),
(N'Manual: calibracion de sensores de temperatura y humedad', 'manual',
 N'Los sensores de temperatura y humedad se calibran cada seis meses. Para la temperatura se compara con un termometro de referencia a 20 grados; para la humedad, con una camara de sal saturada que da 75 por ciento. Si la desviacion es mayor de 1 grado o de 3 puntos de humedad, ajustar el offset en el firmware del nodo. Anotar la fecha y el valor del ajuste en la ficha del sensor. Un sensor que queda fuera de tolerancia despues de ajustar se retira y se cambia.'),
(N'Guia: severidad de las alarmas y tiempos de respuesta', 'guia',
 N'Las alarmas se clasifican en cuatro niveles. Baja: no afecta al servicio, se atiende en la jornada siguiente. Media: puede afectar a la medicion, respuesta en cuatro horas. Alta: riesgo para equipos o personas, respuesta en una hora. Critica: parada de una instalacion o dano inmediato, respuesta inmediata y aviso al responsable. Cada alarma pasa por tres estados: abierta, en curso y cerrada. Al cerrar una incidencia hay que indicar la causa y la solucion para poder consultarla despues.'),
(N'Procedimiento: corte de luz y arranque de equipos', 'procedimiento',
 N'Tras un corte de luz, los equipos importantes pueden no volver a arrancar solos. Orden de arranque: 1) Comprobar el cuadro electrico y el estado del SAI. 2) Arrancar primero la refrigeracion de la sala de servidores. 3) Encender despues los servidores y la red. 4) Revisar los nodos IoT y que vuelven a enviar lecturas. 5) Comprobar que no hay alarmas falsas generadas durante el corte. Si el SAI se ha quedado sin bateria, anotarlo en una incidencia para revisar su autonomia.');
GO

SELECT DocumentoId, Tipo, Titulo, LEN(Contenido) AS Caracteres
FROM dbo.Documentos
ORDER BY DocumentoId;
GO
