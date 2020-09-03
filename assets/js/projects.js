import {create_element} from "./util"
import Modal from "./modals"

import "phoenix_html"

import {Socket} from "phoenix"
import LiveSocket from "phoenix_live_view"

const hooks = {}
hooks.add_project = {
  mounted() {
    btn_add_project.addEventListener("click", () => {
      const selected_encoder = select_encoder.value

      const options = {}
      for (const param_name of Object.keys(encoders[selected_encoder])) {
        const param = encoders[selected_encoder][param_name]
        const e = document.getElementById(`opt_${selected_encoder}_${param_name}`)
        if (param.requires) {
          const req_e = document.getElementById(`opt_${selected_encoder}_${param.requires}`)
          if (param.requires_values.includes(req_e)) continue
        }
        if (param_name == "resolution") {
          const res_dims = e.value.split("x")
          options["--width"] = res_dims[0]
          options["--height"] = res_dims[1]
        } else {
          options[param_name] = e.value
        }
      }
      
      const params = []
      for (const param_name of Object.keys(options)) {
        if (options[param_name].length > 0) {
          if (param_name.startsWith("--")) {
            params.push(`${param_name}=${options[param_name]}`)
          } else if (param_name.startsWith("-")) {
            params.push(param_name)
            params.push(options[param_name])
          }
        } else {
          params.push(param_name)
        }
      }
      
      const confirm_modal = new Modal({title: "Create Project"})
      confirm_modal.show()

      confirm_modal.get_body().style.textAlign = "center"

      confirm_modal.confirm = create_element(confirm_modal, "button")
      confirm_modal.confirm.textContent = "Confirm"
      confirm_modal.confirm.focus()
      confirm_modal.confirm.addEventListener("click", () => {
        this.pushEvent("add_project", {files: [], params: params}, (reply, _ref) => {
          confirm_modal.close()
          if (reply.success) {
          } else {
            const err_modal = new Modal({title: "Error"})
            const reason_t = create_element(err_modal, "div")
            reason_t.textContent = "Reason:"
            const reason = create_element(err_modal, "div")
            reason.textContent = reply.reason
            err_modal.show()
          }
        })
      })
    })
  },

  updated() {
    console.log("Updated", this)
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {hooks: hooks, params: {_csrf_token: csrfToken}})
liveSocket.connect()

const encoders = JSON.parse(document.getElementById("encoders").textContent)

for (const encoder_name of Object.keys(encoders)) {
  for (const param_name of Object.keys(encoders[encoder_name])) {
    const param = encoders[encoder_name][param_name]
    const e = document.getElementById(`opt_${encoder_name}_${param_name}`)
    if (param.requires) {
      const req_e = document.getElementById(`opt_${encoder_name}_${param.requires}`)
      const onchange = () => e.parentElement.classList.toggle("hidden", !param.requires_values.includes(req_e.value))
      req_e.addEventListener("change", onchange)
      onchange()
    }
  }
}

function show_params() {
  for (const encoder_param of encoder_params.children) {
    encoder_param.classList.toggle("hidden", encoder_param.id != `params_${select_encoder.value}`) 
  }
}

select_encoder.addEventListener("change", () => {
  show_params()
})

show_params()
/*
post(`${server}/api/add_project`, payload, e => {
      const resp = JSON.parse(e)
      confirm_modal.close()
      if (!("success" in resp)) {
        const err_modal = new Modal({title: "Error"})
        const reason_t = create_element(err_modal, "div")
        reason_t.textContent = "Reason:"
        const reason = create_element(err_modal, "div")
        reason.textContent = e
        err_modal.show()
      } else if (!resp["success"]) {
        const err_modal = new Modal({title: "Error"})
        const reason_t = create_element(err_modal, "div")
        reason_t.textContent = "Reason:"
        const reason = create_element(err_modal, "div")
        reason.textContent = resp["reason"]
        err_modal.show()
      } else {
        update_projects()
        if (password.length > 0)
          set_cookie(`pw-${server}`, password)
      }
    })*/
console.log("ASD")