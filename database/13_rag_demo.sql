-- Mini-SCADA: demo del RAG paso a paso con una sola pregunta.
-- Muestra lo que pide el enunciado: la pregunta, los documentos que recupera la
-- busqueda, el contexto que recibe el modelo y la respuesta final.
-- Hace falta haber ejecutado antes 12_rag.sql, que crea usp_PreguntarRAG.

USE MiniScada;
GO

DECLARE @Pregunta  NVARCHAR(500) = N'el sensor de CO2 de la oficina marca siempre lo mismo, que hago';
DECLARE @Respuesta NVARCHAR(MAX), @Contexto NVARCHAR(MAX);

-- El procedimiento recupera los documentos, monta el prompt y llama al modelo
EXEC dbo.usp_PreguntarRAG @Pregunta = @Pregunta, @UsarRAG = 1, @Cantidad = 2,
     @Respuesta = @Respuesta OUTPUT, @Contexto = @Contexto OUTPUT;

-- Los mismos documentos, con la distancia para ver por que se han elegido
DECLARE @Vector VECTOR(768) = AI_GENERATE_EMBEDDINGS(@Pregunta USE MODEL ModeloEmbeddings);

CREATE TABLE #Demo (Orden INT IDENTITY(1,1), Paso NVARCHAR(40), Texto NVARCHAR(MAX));

INSERT #Demo (Paso, Texto) VALUES (N'1. Pregunta', @Pregunta);

INSERT #Demo (Paso, Texto)
SELECT TOP (2) N'2. Documento recuperado',
       CONCAT(Titulo, N' (distancia ',
              CAST(CAST(VECTOR_DISTANCE('cosine', Embedding, @Vector) AS DECIMAL(6,4)) AS NVARCHAR(10)), N')')
FROM dbo.Documentos
WHERE Embedding IS NOT NULL
ORDER BY VECTOR_DISTANCE('cosine', Embedding, @Vector);

INSERT #Demo (Paso, Texto) VALUES (N'3. Contexto para el modelo', REPLACE(@Contexto, CHAR(10), N' '));
INSERT #Demo (Paso, Texto) VALUES (N'4. Respuesta', @Respuesta);

-- Cada texto partido en lineas de 120 caracteres para que quepa en la rejilla
SELECT CASE WHEN g.value = 1 THEN d.Paso ELSE N'' END AS Paso,
       SUBSTRING(d.Texto, (g.value - 1) * 120 + 1, 120) AS Texto
FROM #Demo d
CROSS APPLY GENERATE_SERIES(CAST(1 AS INT), CAST((LEN(d.Texto) + 119) / 120 AS INT)) AS g
ORDER BY d.Orden, g.value;

DROP TABLE #Demo;
GO
