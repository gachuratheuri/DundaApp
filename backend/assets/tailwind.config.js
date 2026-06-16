// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration
//
// ChromaNoir production token set (QA §1.2). This compiles the design system
// natively into the Phoenix production binary, replacing the dev-only CDN.
//
// To finish wiring the pipeline (cannot be executed in this environment):
//   1. Add to mix.exs deps: {:tailwind, "~> 0.2"}, {:esbuild, "~> 0.8"}
//   2. Configure :tailwind / :esbuild profiles in config/config.exs
//   3. Add Plug.Static for "assets" in DundaWeb.Endpoint
//   4. Link compiled /assets/app.css from the root layout (replace the CDN tag)
//   5. Run: mix assets.setup && mix assets.build

const plugin = require('tailwindcss/plugin')

module.exports = {
  content: [
    './js/**/*.js',
    '../lib/dunda_web/controllers/**/*.ex',
    '../lib/dunda_web/live/**/*.ex',
    '../lib/dunda_web/components/**/*.ex',
    '../lib/dunda_web/**/*.heex'
  ],
  theme: {
    extend: {
      colors: {
        // ChromaNoir canonical tokens
        voidblack: '#000000',
        abyssnavy: '#060607',
        surfacegray: '#08080A',
        purewhite: '#FCFCFD',
        periwinkle: '#A99FB8',
        chromaviolet: '#B026FF',
        magentaacid: '#FF1C5E',
        goldprestige: '#F4F800',
        opticyan: '#00F0FF',
        acidgreen: '#39FF14',
        // Legacy aliases (retained so pre-migration classes still compile)
        nebulamagenta: '#FF1C5E',
        solfeggiogold: '#F4F800'
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        display: ['Oswald', 'sans-serif'],
        oswald: ['Oswald', 'sans-serif'],
        mono: ['Inter', 'ui-monospace', 'monospace']
      }
    }
  },
  plugins: [
    require('@tailwindcss/forms'),
    // Phoenix LiveView helper variants for transition states.
    plugin(({ addVariant }) => addVariant('phx-no-feedback', ['.phx-no-feedback&', '.phx-no-feedback &'])),
    plugin(({ addVariant }) => addVariant('phx-click-loading', ['.phx-click-loading&', '.phx-click-loading &'])),
    plugin(({ addVariant }) => addVariant('phx-submit-loading', ['.phx-submit-loading&', '.phx-submit-loading &'])),
    plugin(({ addVariant }) => addVariant('phx-change-loading', ['.phx-change-loading&', '.phx-change-loading &']))
  ]
}
