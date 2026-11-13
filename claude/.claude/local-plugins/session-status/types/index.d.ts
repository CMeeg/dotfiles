/** The model and effort the main loop last sent a request with. */
export type ModelInfo = { model: string; effort?: string | number }

/** One rate-limit window of the subscription, as the last API response reported it. */
export type Limit = { kind: string; percentUsed: number; resetsAt?: string }

/** One category of the context window, as /context breaks it down. */
export type Slice = { name: string; tokens: number; color: string; kind: 'used' | 'free' | 'buffer' }

/** The context window by category. */
export type Reading = {
  slices: Slice[]
  total: number // tokens in use
  window: number // the window measured against
  percent: number
  compactsAt?: number // where auto-compaction runs, when it is on
}

declare module 'claude-code' {
  interface PluginState {
    'session-status': {
      model: ModelInfo | null
      limits: Limit[]
      meterView: number
      meterTick: number
      reading: Reading | null
      isKeyShown: boolean
    }
  }
}
