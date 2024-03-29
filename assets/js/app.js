import { create_element } from "./util"
import { create_window, Modal } from "./window"

import "phoenix_html"

import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

import topbar from "../vendor/topbar"

topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", info => topbar.show())
window.addEventListener("phx:page-loading-stop", info => topbar.hide())

const hooks = {}

const re_args = /"[^"\\]*(?:\\[\S\s][^"\\]*)*"|'[^'\\]*(?:\\[\S\s][^'\\]*)*'|\/[^\/\\]*(?:\\[\S\s][^\/\\]*)*\/[gimy]*(?=\s|$)|(?:\\\s|\S)+/g

hooks.load_encoders = {
  mounted() {
    btn_add_project.addEventListener("click", () => {
      const selected_encoder = select_encoder.value

      const enc_params = [...opt_encoder_params.value.matchAll(re_args)].flat()

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
        encoder: selected_encoder,
        encoder_params: enc_params,
        split_min_frames: opt_split_min_frames.value,
        split_max_frames: opt_split_max_frames.value,
        priority: opt_extra_priority.value,
        name: opt_extra_name.value,
        on_complete: opt_extra_on_complete.value,
        on_complete_params: [...opt_extra_on_complete_params.value.matchAll(re_args)].flat(),
        ffmpeg_params: [...opt_extra_ffmpeg_params.value.matchAll(re_args)].flat(),
        start_after_split: opt_extra_start_after_split.checked,
        copy_timestamps: opt_extra_copy_timestamps.checked
      }

      console.log(params)

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
            reason.innerHTML = reply.reason
          }
        })
      })
    })

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

hooks.select_project = {
  mounted() {
    this.el.addEventListener("click", e => {
      this.pushEvent("select_project", {
        id: this.el.dataset.id,
        multi: e.ctrlKey
      })
    })
  }
}

hooks.settings_run_action = {
  mounted() {
    this.el.addEventListener("click", () => {
      const params = [...document.getElementById(`${this.el.id}_params`).value.matchAll(re_args)].flat()
      this.pushEvent("run_complete_action", {
        action: document.getElementById(`${this.el.id}_list`).value,
        params: params
      })
    })
  }
}

hooks.settings_action = {
  mounted() {
    this.el.addEventListener("change", () => {
      const original_value = this.el.getAttribute("original-value")
      const settings_action_params = document.getElementById(`${this.el.id}_params`)
      const original_params = settings_action_params.getAttribute("original-value")

      const unchanged = ((original_value == "" && this.el.value == "No action") ||
        original_value == this.el.value) && original_params == settings_action_params.value

      document.getElementById(`${this.el.id}_save`).classList.toggle("hidden", unchanged)
      document.getElementById(`${this.el.id}_cancel`).classList.toggle("hidden", unchanged)
    })
  }
}

hooks.settings_action_params = {
  mounted() {
    const on_change = () => {
      const settings_action = document.getElementById(this.el.getAttribute("source"))
      const original_value = settings_action.getAttribute("original-value")
      const original_params = this.el.getAttribute("original-value")

      const unchanged = ((original_value == "" && settings_action.value == "No action") ||
        original_value == settings_action.value) && original_params == this.el.value

      document.getElementById(`${settings_action.id}_save`).classList.toggle("hidden", unchanged)
      document.getElementById(`${settings_action.id}_cancel`).classList.toggle("hidden", unchanged)
    }
    this.el.addEventListener("change", on_change)
    this.el.addEventListener("keyup", on_change)
  }
}

hooks.settings_action_cancel = {
  mounted() {
    this.el.addEventListener("click", () => {
      const settings_action = document.getElementById(this.el.getAttribute("source"))
      const settings_action_params = document.getElementById(`${settings_action.id}_params`)

      const original_value = settings_action.getAttribute("original-value")
      const original_params = settings_action_params.getAttribute("original-value")

      if (original_value == "") {
        settings_action.value = "No action"
      } else {
        settings_action.value = original_value
      }
      settings_action_params.value = original_params

      document.getElementById(`${settings_action.id}_save`).classList.toggle("hidden", true)
      document.getElementById(`${settings_action.id}_cancel`).classList.toggle("hidden", true)
    })
  }
}

hooks.settings_action_save = {
  mounted() {
    this.el.addEventListener("click", () => {
      const settings_action = document.getElementById(this.el.getAttribute("source"))
      const settings_action_params = document.getElementById(`${settings_action.id}_params`)

      const original_value = settings_action.getAttribute("original-value")
      const original_params = settings_action_params.getAttribute("original-value")

      const params = [...settings_action_params.value.matchAll(re_args)].flat()

      this.pushEvent("set_action", {
        from_action: original_value || null,
        action: settings_action.value,
        from_params: original_params,
        params: params
      }, (reply, _ref) => {
        if (!reply.success) {
          const err_modal = new Modal({
            title: "Error"
          })
          const reason_t = create_element(err_modal, "div")
          reason_t.textContent = "Reason:"
          const reason = create_element(err_modal, "div")
          reason.innerHTML = reply.reason
        }
      })
    })
  }
}

hooks.settings_delete = {
  mounted() {
    this.el.addEventListener("click", () => {
      this.pushEvent("delete_project", {

      })
    })
  }
}

hooks.settings_change_encoder_params = {
  mounted() {
    this.el.addEventListener("click", () => {
      this.el.contentEditable = true
      this.el.classList.toggle("div-editing", true)
      this.el.focus()
      document.getElementById(`${this.el.id}_save`).classList.toggle("hidden", false)
      document.getElementById(`${this.el.id}_cancel`).classList.toggle("hidden", false)
    })
  }
}

hooks.settings_encoder_params_save = {
  mounted() {
    this.el.addEventListener("click", () => {
      const settings_encoder_params = document.getElementById(this.el.getAttribute("source"))
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
          from: settings_encoder_params.getAttribute("original-value"),
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
            reason.innerHTML = reply.reason
          }
        })
      })
    })
  }
}

hooks.settings_encoder_params_cancel = {
  mounted() {
    this.el.addEventListener("click", () => {
      const settings_encoder_params = document.getElementById(this.el.getAttribute("source"))
      settings_encoder_params.textContent = settings_encoder_params.getAttribute("original-value")
      settings_encoder_params.contentEditable = false
      settings_encoder_params.classList.toggle("div-editing", false)
      document.getElementById(`${settings_encoder_params.id}_save`).classList.toggle("hidden", true)
      this.el.classList.toggle("hidden", true)
    })
  }
}

hooks.settings_change_priority = {
  mounted() {
    this.el.addEventListener("change", () => {
      const original_value = this.el.getAttribute("original-value")
      document.getElementById(`${this.el.id}_save`).classList.toggle("hidden", original_value == this.el.value)
      document.getElementById(`${this.el.id}_cancel`).classList.toggle("hidden", original_value == this.el.value)
    })
  }
}

hooks.settings_priority_save = {
  mounted() {
    this.el.addEventListener("click", () => {
      const settings_priority = document.getElementById(this.el.getAttribute("source"))
      const original_value = settings_priority.getAttribute("original-value")
      this.pushEvent("set_priority", {
        from: original_value,
        priority: settings_priority.value
      }, (reply, _ref) => {
        if (!reply.success) {
          const err_modal = new Modal({
            title: "Error"
          })
          const reason_t = create_element(err_modal, "div")
          reason_t.textContent = "Reason:"
          const reason = create_element(err_modal, "div")
          reason.innerHTML = reply.reason
        }
      })
    })
  }
}

hooks.settings_priority_cancel = {
  mounted() {
    this.el.addEventListener("click", () => {
      const settings_priority = document.getElementById(this.el.getAttribute("source"))
      const original_value = settings_priority.getAttribute("original-value")
      settings_priority.value = original_value
      document.getElementById(`${settings_priority.id}_save`).classList.toggle("hidden", true)
      this.el.classList.toggle("hidden", true)
    })
  }
}

hooks.settings_change_name = {
  mounted() {
    this.el.addEventListener("click", () => {
      this.el.contentEditable = true
      this.el.classList.toggle("div-editing", true)
      this.el.focus()
      document.getElementById(`${this.el.id}_save`).classList.toggle("hidden", false)
      document.getElementById(`${this.el.id}_cancel`).classList.toggle("hidden", false)
    })
  }
}

hooks.settings_name_save = {
  mounted() {
    this.el.addEventListener("click", () => {
      const settings_name = document.getElementById(this.el.getAttribute("source"))
      this.pushEvent("set_name", {
        name: settings_name.textContent
      }, (reply, _ref) => {
        if (reply.success) {
          settings_name.original_value = settings_name.textContent
        } else {
          const err_modal = new Modal({
            title: "Error"
          })
          const reason_t = create_element(err_modal, "div")
          reason_t.textContent = "Reason:"
          const reason = create_element(err_modal, "div")
          reason.innerHTML = reply.reason
        }
      })
    })
  }
}

hooks.settings_name_cancel = {
  mounted() {
    this.el.addEventListener("click", () => {
      const settings_name = document.getElementById(this.el.getAttribute("source"))
      settings_name.textContent = settings_name.getAttribute("original-value")
      settings_name.contentEditable = false
      settings_name.classList.toggle("div-editing", false)
      document.getElementById(`${settings_name.id}_save`).classList.toggle("hidden", true)
      this.el.classList.toggle("hidden", true)
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
            reason.innerHTML = reply.reason
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
