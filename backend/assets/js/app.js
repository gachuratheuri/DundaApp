// Tiketa organiser portal — client bundle.
//
// Bundled by esbuild from the `phoenix` / `phoenix_live_view` hex packages
// (resolved via NODE_PATH=../deps), replacing the CDN UMD globals + inline
// LiveSocket wiring that previously lived in the root layout.

import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const Hooks = {
  // Animated count-up for dashboard KPIs (cubic ease-out).
  CountUp: {
    mounted() {
      const target = parseInt(this.el.getAttribute("data-target") || "0", 10)
      const duration = 1200
      const startTime = performance.now()
      const prefix = this.el.getAttribute("data-prefix") || ""
      const suffix = this.el.getAttribute("data-suffix") || ""

      const animate = (currentTime) => {
        const elapsed = currentTime - startTime
        const progress = Math.min(elapsed / duration, 1)
        const ease = 1 - Math.pow(1 - progress, 3)
        const currentVal = Math.floor(ease * target)

        this.el.innerText = prefix + currentVal.toLocaleString() + suffix

        if (progress < 1) {
          requestAnimationFrame(animate)
        } else {
          this.el.innerText = prefix + target.toLocaleString() + suffix
        }
      }

      requestAnimationFrame(animate)
    },
  },
}

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
})

liveSocket.connect()
window.liveSocket = liveSocket
