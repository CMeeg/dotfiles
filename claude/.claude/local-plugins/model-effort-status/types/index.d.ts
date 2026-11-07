/** The model and effort the main loop last sent a request with. */
export type ModelInfo = { model: string; effort?: string | number }

declare module 'claude-code' {
  interface PluginState {
    'model-effort-status': { info: ModelInfo | null }
  }
}
