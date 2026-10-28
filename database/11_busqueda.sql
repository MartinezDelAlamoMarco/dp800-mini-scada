-- Mini-SCADA: busqueda semantica con VECTOR_DISTANCE.
-- Se convierte la pregunta en un vector con el mismo modelo que los documentos y
-- se ordenan los documentos por distancia coseno (cuanto menor, mas parecidos).
-- La distancia coseno compara la direccion de los vectores y no su longitud, que
-- es lo que importa en embeddings de texto, donde la longitud del texto no
-- cambia el tema de lo que habla.

USE MiniScada;
GO

CREATE OR ALTER PROCEDURE dbo.usp_BuscarDocumentos
    @Pregunta NVARCHAR(500),
    @Cantidad INT = 3
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Vector VECTOR(768) = AI_GENERATE_EMBEDDINGS(@Pregunta USE MODEL ModeloEmbeddings);

    SELECT TOP (@Cantidad)
           DocumentoId, Titulo, Tipo,
           CAST(VECTOR_DISTANCE('cosine', Embedding, @Vector) AS DECIMAL(6,4)) AS Distancia
    FROM dbo.Documentos
    WHERE Embedding IS NOT NULL
    ORDER BY VECTOR_DISTANCE('cosine', Embedding, @Vector);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_BuscarAlarmasSimilares
    @Pregunta NVARCHAR(500),
    @Cantidad INT = 3
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Vector VECTOR(768) = AI_GENERATE_EMBEDDINGS(@Pregunta USE MODEL ModeloEmbeddings);

    SELECT TOP (@Cantidad)
           AlarmaId, LEFT(Descripcion, 90) AS Descripcion, Severidad,
           CAST(VECTOR_DISTANCE('cosine', Embedding, @Vector) AS DECIMAL(6,4)) AS Distancia
    FROM dbo.Alarmas
    WHERE Embedding IS NOT NULL
    ORDER BY VECTOR_DISTANCE('cosine', Embedding, @Vector);
END;
GO

-- Las cinco preguntas de prueba. Estan escritas como las diria un tecnico, sin
-- copiar las palabras de los manuales. Para cada una se guarda el primer y el
-- segundo documento que devuelve la busqueda, con su distancia.
CREATE TABLE #Preguntas (Id INT NOT NULL, Pregunta NVARCHAR(500) NOT NULL);
INSERT #Preguntas (Id, Pregunta) VALUES
    (1, N'el sensor de CO2 marca siempre el mismo valor'),
    (2, N'se fue la luz y el aire de la sala de los servidores no vuelve a arrancar'),
    (3, N'hay mucha humedad en el almacen, creo que hay agua'),
    (4, N'la bomba no da presion y casi no sale agua'),
    (5, N'cuanto tiempo tengo para atender una alarma critica');

CREATE TABLE #Respuesta (Orden INT IDENTITY(1,1), DocumentoId INT, Titulo NVARCHAR(200), Tipo NVARCHAR(30), Distancia DECIMAL(6,4));
CREATE TABLE #Ranking (Id INT, Posicion INT, Titulo NVARCHAR(200), Distancia DECIMAL(6,4));

DECLARE @i INT = 1, @Pregunta NVARCHAR(500);
WHILE @i <= 5
BEGIN
    SELECT @Pregunta = Pregunta FROM #Preguntas WHERE Id = @i;
    TRUNCATE TABLE #Respuesta;
    INSERT #Respuesta (DocumentoId, Titulo, Tipo, Distancia)
    EXEC dbo.usp_BuscarDocumentos @Pregunta = @Pregunta, @Cantidad = 2;
    INSERT #Ranking (Id, Posicion, Titulo, Distancia)
    SELECT @i, Orden, Titulo, Distancia FROM #Respuesta;
    SET @i += 1;
END;

SELECT p.Id, p.Pregunta,
       r1.Titulo AS Primero, r1.Distancia AS Dist1,
       r2.Titulo AS Segundo, r2.Distancia AS Dist2
FROM #Preguntas p
JOIN #Ranking r1 ON r1.Id = p.Id AND r1.Posicion = 1
JOIN #Ranking r2 ON r2.Id = p.Id AND r2.Posicion = 2
ORDER BY p.Id;

DROP TABLE #Preguntas, #Respuesta, #Ranking;
GO

-- Lo mismo con las alarmas: las parecidas a un problema nuevo
EXEC dbo.usp_BuscarAlarmasSimilares N'el servidor se calienta demasiado';
GO
