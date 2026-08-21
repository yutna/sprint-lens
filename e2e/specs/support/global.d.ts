/**
 * The LiveView client publishes its socket on `window` (see
 * `assets/js/app.js`), which is how a spec can ask whether the connection is
 * up or drop it on purpose.
 *
 * It is optional because it genuinely is: the script has not run yet on the
 * first paint, which is exactly the window `waitForLiveView` polls through.
 */
declare global {
  interface Window {
    liveSocket?: {
      isConnected(): boolean
      connect(): void
      disconnect(): void
    }
  }
}

export {}
