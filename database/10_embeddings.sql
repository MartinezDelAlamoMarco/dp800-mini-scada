-- Mini-SCADA: generar los embeddings de las alarmas y de los documentos.
-- Necesita Ollama y nginx en marcha y el modelo externo ModeloEmbeddings creado
-- (ver setup/00_verificar_entorno.sql). Se puede repetir sin problema: solo
-- rellena las filas que todavia no tienen embedding.

USE MiniScada;
GO

-- Alarmas: el texto que se convierte en vector es la descripcion
UPDATE dbo.Alarmas
SET Embedding = AI_GENERATE_EMBEDDINGS(Descripcion USE MODEL ModeloEmbeddings)
WHERE Embedding IS NULL;
GO

-- Documentos: titulo y contenido juntos, para que el titulo tambien cuente
UPDATE dbo.Documentos
SET Embedding = AI_GENERATE_EMBEDDINGS(CONCAT(Titulo, N'. ', Contenido) USE MODEL ModeloEmbeddings)
WHERE Embedding IS NULL;
GO

-- Comprobacion: cuantas filas tienen embedding y de cuantas dimensiones
SELECT N'Alarmas' AS Tabla,
       COUNT(*) AS Filas,
       SUM(CASE WHEN Embedding IS NOT NULL THEN 1 ELSE 0 END) AS ConEmbedding,
       MAX(VECTORPROPERTY(Embedding, 'Dimensions')) AS Dimensiones
FROM dbo.Alarmas
UNION ALL
SELECT N'Documentos', COUNT(*),
       SUM(CASE WHEN Embedding IS NOT NULL THEN 1 ELSE 0 END),
       MAX(VECTORPROPERTY(Embedding, 'Dimensions'))
FROM dbo.Documentos;
GO
