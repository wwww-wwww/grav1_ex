import "../css/app.scss"

import { create_element } from "./util"
import { create_window, Modal } from "./window"

import "phoenix_html"

import { Socket } from "phoenix"
import LiveSocket from "phoenix_live_view"

import NProgress from "nprogress"

window.addEventListener("phx:page-loading-start", _ => NProgress.start())
window.addEventListener("phx:page-loading-stop", _ => NProgress.done())

const hooks = {}

const re_args = /"[^"\\]*(?:\\[\S\s][^"\\]*)*"|'[^'\\]*(?:\\[\S\s][^'\\]*)*'|\/[^\/\\]*(?:\\[\S\s][^\/\\]*)*\/[gimy]*(?=\s|$)|(?:\\\s|\S)+/g

hooks.load_encoders = {
  mounted() {
    const encoders = JSON.parse(document.getElementById("encoders").textContent)

    btn_add_project.addEventListener("click", () => {
      const selected_encoder = select_encoder.value

      const options = {}
      const overrides = []
      for (const param_name of Object.keys(encoders[selected_encoder])) {
        const param = encoders[selected_encoder][param_name].data
        const e = document.getElementById(`opt_${selected_encoder}_${param_name}`)
        if (param.requires) {
          const req_e = document.getElementById(`opt_${selected_encoder}_${param.requires}`)
          if (!param.requires_values.includes(req_e.value)) continue
        }
        if (param.overrides) {
          if (param.overrides[e.value]) {
            overrides.push(...param.overrides[e.value])
          }
        }
        if (param_name == "Resolution") {
          if (e.value != "custom") {
            const res_dims = e.value.split("x")
            options["--width"] = res_dims[0]
            options["--height"] = res_dims[1]
          }
        } else if (param.type == "flag") {
          if (e.checked) options[param_name] = true
        } else {
          options[param_name] = e.value
        }
      }

      const enc_params = []
      for (const param_name of Object.keys(options)) {
        const param = encoders[selected_encoder][param_name].data
        if (options[param_name].length > 0) {
          if (param.oneword) {
            enc_params.push(`${param_name}=${options[param_name]}`)
          } else if (param.type == "flag") {
            enc_params.push(param_name)
          } else {
            enc_params.push(param_name)
            enc_params.push(options[param_name])
          }
        } else {
          enc_params.push(param_name)
        }
      }

      enc_params.push(...overrides)
      enc_params.push(...[...opt_extra_encoder_params.value.matchAll(re_args)].flat())

      const files = []
      for (const c of files_list.children) {
        if (c.tagName == "DIV" && c.children[0].value.length > 0) {
          let filename = c.children[0].value
          if (filename[0] == "\"" && filename.substr(-1) == "\"")
            filename = filename.substr(1, filename.length - 2)
          files.push(filename)
        }
      }

      const params = {
        encoder_params: enc_params,
        split_min_frames: opt_split_min_frames.value,
        split_max_frames: opt_split_max_frames.value,
        priority: opt_extra_priority.value,
        name: opt_extra_name.value,
        on_complete: opt_extra_on_complete.value,
        on_complete_params: [...opt_extra_on_complete_params.value.matchAll(re_args)].flat(),
        ffmpeg_params: [...opt_extra_ffmpeg_params.value.matchAll(re_args)].flat(),
        start_after_split: opt_extra_start_after_split.checked,
        encoder: selected_encoder
      }

      const confirm_modal = new Modal({
        title: "Create Project"
      })

      confirm_modal.get_body().style.textAlign = "center"

      confirm_modal.confirm = create_element(confirm_modal, "button")
      confirm_modal.confirm.textContent = "Confirm"
      confirm_modal.confirm.focus()
      confirm_modal.confirm.addEventListener("click", () => {
        this.pushEvent("add_project", { files: files, params: params }, (reply, _ref) => {
          confirm_modal.close()
          if (!reply.success) {
            const err_modal = new Modal({
              title: "Error"
            })
            const reason_t = create_element(err_modal, "div")
            reason_t.textContent = "Reason:"
            const reason = create_element(err_modal, "div")
            reason.textContent = reply.reason
          }
        })
      })
    })

    for (const encoder_name of Object.keys(encoders)) {
      for (const param_name of Object.keys(encoders[encoder_name])) {
        const param = encoders[encoder_name][param_name].data
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

    this.el.parentElement.removeChild(this.el)

    btn_create_add_project.addEventListener("click", () => {
      const window_add_prj = create_window("Add Project", {})
      window_add_prj.show()
      const _body = window_add_prj.get_body()
      while (_body.firstChild) _body.removeChild(_body.firstChild)
      window_add_prj.get_body().appendChild(this.el)
    })
  },
  destroyed() {
    create_window("Add Project", {}).close()
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

hooks.settings_actions = {
  mounted() {
    this.el.addEventListener("click", () => {
      const params = [...on_complete_action_params.value.matchAll(re_args)].flat()
      this.pushEvent("run_complete_action", {
        id: this.el.dataset.id,
        action: on_complete_actions.value,
        params: params
      })
    })
  }
}

hooks.settings_change_encoder_params = {
  mounted() {
    this.el.original_value = this.el.textContent
    this.el.addEventListener("click", () => {
      this.el.contentEditable = true
      this.el.classList.toggle("div-editing", true)
      this.el.focus()
      settings_encoder_params_save.classList.toggle("hidden", false)
      settings_encoder_params_cancel.classList.toggle("hidden", false)
    })
  }
}

hooks.settings_encoder_params_save = {
  mounted() {
    this.el.addEventListener("click", () => {
      const params = [...settings_encoder_params.textContent.matchAll(re_args)].flat()

      const confirm_modal = new Modal({
        title: "Reset encode"
      })

      confirm_modal.get_body().style.textAlign = "center"

      for (const param of params) {
        const e = create_element(confirm_modal, "div")
        e.textContent = param
      }

      confirm_modal.confirm = create_element(confirm_modal, "button")
      confirm_modal.confirm.textContent = "Confirm"
      confirm_modal.confirm.focus()
      confirm_modal.confirm.addEventListener("click", () => {
        this.pushEvent("reset_project", {
          id: this.el.dataset.id,
          encoder_params: params
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
          }
        })
      })
    })
  }
}

hooks.settings_encoder_params_cancel = {
  mounted() {
    this.el.addEventListener("click", () => {
      settings_encoder_params.textContent = settings_encoder_params.original_value
      settings_encoder_params.contentEditable = false
      settings_encoder_params.classList.toggle("div-editing", false)
      settings_encoder_params_save.classList.toggle("hidden", true)
      settings_encoder_params_cancel.classList.toggle("hidden", true)
    })
  }
}

hooks.view_user_client = {
  mounted() {
    this.el.children[4].addEventListener("click", () => {
      const modal = new Modal({ title: "Max workers" })
      modal.get_body().style.textAlign = "center"

      let row = create_element(modal, "div")

      const input_workers = create_element(row, "input")
      input_workers.type = "number"
      input_workers.value = this.el.children[4].textContent

      row = create_element(modal, "div")
      const btn_apply = create_element(row, "input")
      btn_apply.type = "submit"
      btn_apply.value = "Apply"
      btn_apply.addEventListener("click", () => {
        this.pushEvent("set_workers", {
          socket_id: this.el.children[1].textContent,
          max_workers: input_workers.value
        }, (reply, _ref) => {
          if (!reply.success) {
            const err_modal = new Modal({
              title: "Error"
            })
            const reason_t = create_element(err_modal, "div")
            reason_t.textContent = "Reason:"
            const reason = create_element(err_modal, "div")
            reason.textContent = reply.reason
          } else {
            modal.close()
          }
        })
      })
      modal.show()
      input_workers.focus()
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

document.liveSocket = liveSocket

liveSocket.connect()