import "../css/app.scss"

import "phoenix_html"

import {Socket} from "phoenix"
import LiveSocket from "phoenix_live_view"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const hooks = {}
hooks.encoders = {
  mounted() {
    show_params()
  }
}

let liveSocket = new LiveSocket("/live", Socket, {hooks: hooks, params: {_csrf_token: csrfToken}})
liveSocket.connect()

function show_params() {
  for (const encoder_param of encoder_params.children) {
    encoder_param.classList.toggle("hidden", encoder_param.id != `params_${select_encoder.value}`) 
  }
}

select_encoder.addEventListener("change", () => {
  show_params()
})

export default liveSocket
