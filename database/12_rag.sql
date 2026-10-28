-- Mini-SCADA: RAG (generacion aumentada con recuperacion) con un modelo local.
-- El flujo es: pregunta -> se buscan los documentos mas parecidos (como en
-- 11_busqueda.sql) -> se meten en el prompt como contexto -> el modelo de
-- lenguaje contesta usando solo ese contexto.
--
-- El modelo de lenguaje corre en Ollama (hay que haberlo descargado antes con
-- "ollama pull hf.co/bartowski/Llama-3.2-3B-Instruct-GGUF:Q4_K_M") y se llama por el mismo proxy HTTPS que el de los
-- embeddings. SQL Server solo permite un modelo externo de tipo embeddings, asi
-- que para generar texto uso sp_invoke_external_rest_endpoint contra /api/chat.
--
-- Ejecutar el script entero con F5: crea el procedimiento y hace la comparacion
-- de cuatro preguntas, sin RAG y con RAG. Tarda un par de minutos la primera vez,
-- porque Ollama tiene que cargar el modelo.

USE MiniScada;
GO

CREATE OR ALTER PROCEDURE dbo.usp_PreguntarRAG
    @Pregunta  NVARCHAR(500),
    @UsarRAG   BIT = 1,
    @Cantidad  INT = 2,
    @Modelo    NVARCHAR(100) = N'hf.co/bartowski/Llama-3.2-3B-Instruct-GGUF:Q4_K_M',
    @Respuesta NVARCHAR(MAX) OUTPUT,
    @Contexto  NVARCHAR(MAX) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Recuperar: los documentos mas parecidos a la pregunta (distancia coseno)
    IF @UsarRAG = 1
    BEGIN
        DECLARE @Vector VECTOR(768) = AI_GENERATE_EMBEDDINGS(@Pregunta USE MODEL ModeloEmbeddings);

        SELECT @Contexto = STRING_AGG(CONCAT(N'[', Titulo, N'] ', Contenido), CHAR(10) + CHAR(10))
        FROM (
            SELECT TOP (@Cantidad) Titulo, Contenido
            FROM dbo.Documentos
            WHERE Embedding IS NOT NULL
            ORDER BY VECTOR_DISTANCE('cosine', Embedding, @Vector)
        ) AS d;
    END;

    -- 2. Montar el prompt
    DECLARE @Sistema NVARCHAR(MAX) =
        N'Eres un asistente de mantenimiento de una instalacion Mini-SCADA. Responde en espanol y en un maximo de tres frases cortas.';
    DECLARE @Usuario NVARCHAR(MAX) = @Pregunta;

    IF @UsarRAG = 1
    BEGIN
        SET @Sistema += N' Usa SOLO la informacion de los documentos que se te dan. Si la respuesta no esta en los documentos, responde exactamente: No lo encuentro en los manuales.';
        SET @Usuario = CONCAT(N'Documentos:', CHAR(10), @Contexto, CHAR(10), CHAR(10), N'Pregunta: ', @Pregunta);
    END;

    DECLARE @Payload NVARCHAR(MAX) = CONCAT(
        N'{"model":"', @Modelo, N'","stream":false,',
        N'"options":{"temperature":0,"seed":42,"num_predict":200},',
        N'"messages":[',
        N'{"role":"system","content":"', STRING_ESCAPE(@Sistema, 'json'), N'"},',
        N'{"role":"user","content":"', STRING_ESCAPE(@Usuario, 'json'), N'"}]}');

    -- 3. Generar: llamada al modelo de lenguaje
    DECLARE @ret INT, @Respuesta_Json NVARCHAR(MAX);
    EXEC @ret = sp_invoke_external_rest_endpoint
        @url      = N'https://localhost:11435/api/chat',
        @method   = 'POST',
        @headers  = N'{"Content-Type":"application/json"}',
        @payload  = @Payload,
        @timeout  = 230,
        @response = @Respuesta_Json OUTPUT;

    SET @Respuesta = COALESCE(JSON_VALUE(@Respuesta_Json, '$.result.message.content'),
                              CONCAT(N'ERROR: ', LEFT(@Respuesta_Json, 300)));
END;
GO

-- Comparacion: la misma pregunta sin RAG y con RAG. Las tres primeras estan en
-- los manuales; la cuarta no esta, y el modelo con RAG debe decir que no la encuentra.
CREATE TABLE #Preguntas (Id INT NOT NULL, Pregunta NVARCHAR(500) NOT NULL);
INSERT #Preguntas (Id, Pregunta) VALUES
    (1, N'cuanto tiempo tengo para atender una alarma de severidad alta'),
    (2, N'cada cuanto se calibran los sensores de temperatura y humedad y con que se comprueban'),
    (3, N'que hago si la presion de la bomba del almacen baja de 1 bar'),
    (4, N'que hago si hay un incendio en la sala de servidores');

CREATE TABLE #Salida (Id INT, Modo NVARCHAR(10), Respuesta NVARCHAR(MAX));

DECLARE @i INT = 1, @Pregunta NVARCHAR(500), @R NVARCHAR(MAX);
WHILE @i <= 4
BEGIN
    SELECT @Pregunta = Pregunta FROM #Preguntas WHERE Id = @i;

    EXEC dbo.usp_PreguntarRAG @Pregunta = @Pregunta, @UsarRAG = 0, @Respuesta = @R OUTPUT;
    INSERT #Salida VALUES (@i, N'sin RAG', @R);

    EXEC dbo.usp_PreguntarRAG @Pregunta = @Pregunta, @UsarRAG = 1, @Respuesta = @R OUTPUT;
    INSERT #Salida VALUES (@i, N'con RAG', @R);

    SET @i += 1;
END;

-- Resultado: cada respuesta partida en lineas de 110 caracteres para poder leerla
SELECT s.Id, s.Modo,
       SUBSTRING(s.Respuesta, (g.value - 1) * 110 + 1, 110) AS Texto
FROM #Salida s
CROSS APPLY GENERATE_SERIES(CAST(1 AS INT), CAST((LEN(s.Respuesta) + 109) / 110 AS INT)) AS g
ORDER BY s.Id, s.Modo DESC, g.value;

DROP TABLE #Preguntas, #Salida;
GO
