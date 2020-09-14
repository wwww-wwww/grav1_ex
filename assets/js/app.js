import "../css/app.scss"

import {create_element} from "./util"
import Modal from "./modals"

import "phoenix_html"

import {Socket} from "phoenix"
import LiveSocket from "phoenix_live_view"

import NProgress from "nprogress"

window.addEventListener("phx:page-loading-start", _ => NProgress.start())
window.addEventListener("phx:page-loading-stop", _ => NProgress.done())

const hooks = {}

hooks.load_encoders = {
  mounted() {
    const encoders = JSON.parse(document.getElementById("encoders").textContent)

    btn_add_project.addEventListener("click", () => {
      const selected_encoder = select_encoder.value

      const options = {}
      for (const param_name of Object.keys(encoders[selected_encoder])) {
        const param = encoders[selected_encoder][param_name]
        const e = document.getElementById(`opt_${selected_encoder}_${param_name}`)
        if (param.requires) {
          const req_e = document.getElementById(`opt_${selected_encoder}_${param.requires}`)
          if (!param.requires_values.includes(req_e.value)) continue
        }
        if (param_name == "resolution") {
          if (e.value != "custom") {
            const res_dims = e.value.split("x")
            options["--width"] = res_dims[0]
            options["--height"] = res_dims[1]
          }
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

      const files = []
      for (const c of files_list.children) {
        if (c.tagName == "DIV" && c.children[0].value.length > 0) {
          let filename = c.children[0].value
          if (filename[0] == "\"" && filename.substr(-1) == "\"")
            filename = filename.substr(1, filename.length - 2)
          files.push(filename)
        }
      }

      const extra_params = {}
      extra_params.split = {
        min_frames: opt_split_min_frames.value,
        max_frames: opt_split_max_frames.value
      }
      extra_params.priority = opt_extra_priority.value
      extra_params.name = opt_extra_name.value

      const confirm_modal = new Modal({
        title: "Create Project"
      })
      confirm_modal.show()

      confirm_modal.get_body().style.textAlign = "center"

      confirm_modal.confirm = create_element(confirm_modal, "button")
      confirm_modal.confirm.textContent = "Confirm"
      confirm_modal.confirm.focus()
      confirm_modal.confirm.addEventListener("click", () => {
        this.pushEvent("add_project", {
          encoder: selected_encoder,
          files: files,
          encoder_params: params,
          extra_params: extra_params
        }, (reply, _ref) => {
          confirm_modal.close()
          if (!reply.success) {
            const err_modal = new Modal({
              title: "Error"
            })
            const reason_t = create_element(err_modal, "div")
            reason_t.textContent = "Reason:"
            const reason = create_element(err_modal, "div")
            reason.textContent = reply.reason
            err_modal.show()
          }
        })
      })
    })

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

    files_list_add.addEventListener("click", () => {
      const e = create_element(null, "div")

      e.input = create_element(e, "input")

      e.remove = create_element(e, "button", "material-icons")
      e.remove.textContent = "clear"
      e.remove.addEventListener("click", () => {
        files_list.removeChild(e)
      })

      files_list.insertBefore(e, files_list_add)
      e.input.focus()
    })
  }
}

hooks.view_project = {
  mounted() {
    this.el.addEventListener("click", () => {
      this.pushEvent("view_project", {
        id: this.el.dataset.id
      })
    })
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  hooks: hooks,
  params: {
    _csrf_token: csrfToken
  }
})
liveSocket.connect()