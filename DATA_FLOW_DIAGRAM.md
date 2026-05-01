# GRAPPL Data Flow Diagram

```mermaid
flowchart LR
  inputVideo[InputVideo] --> ingestWatcher[IngestWatcher]
  ingestWatcher --> inferenceService[InferenceService]
  inferenceService --> clipService[ClipService]
  clipService --> analysisService[AnalysisService]
  analysisService --> supabaseDb[SupabaseDB]
  supabaseDb --> uiLibrary[UILibrary]
```
