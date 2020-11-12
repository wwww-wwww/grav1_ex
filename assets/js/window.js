import "../css/window.scss"
import { create_element } from "./util"

class Window {
  constructor({ root = null, can_close = true, title = null, show = true, modal = false } = {}) {
    this.root = root || document.querySelector("body")
    this.tabs = []
    this.selected_tab = null

    this.drag = null

    if (modal) {
      this.outer = create_element(null, "div", "modal-outer")
      this.e = create_element(this.outer, "div", "modal")
      this.back = create_element(this.outer, "div", "modal-back")
    } else {
      this.e = create_element(null, "div", "window")
      this.e.style.transform = "translate(-50%, -50%)"
    }

    this.top = create_element(this.e, "div", "window-top")
    this.top.addEventListener("mousedown", e => this.drag_start(e))

    this.header = create_element(this.top, "div", "window-header")

    if (can_close) {
      if (modal) {
        this.back.addEventListener("click", _ => this.close())
      }

      this.btn_close = create_element(this.top, "button", "window-close square material-icons")
      this.btn_close.textContent = "close"
      this.btn_close.addEventListener("click", _ => this.close())
    }

    if (title) {
      this.add_title(title)
    }

    if (show) {
      this.show()
    }
  }

  show() {
    this.root.appendChild(this.outer || this.e)
  }

  drag_start(e) {
    if (e.target == this.btn_close) return

    this.top.style.cursor = "grabbing"

    const rect = this.e.getBoundingClientRect()
    this.drag = [
      e.pageX - rect.left,
      e.pageY - rect.top
    ]

    document.addEventListener("mousemove", e => this.drag_move(e))
    document.addEventListener("mouseup", e => this.drag_end(e))
  }

  drag_end(e) {
    if (this.drag == null) return

    this.drag_move(e)
    this.top.style.cursor = ""
    this.drag = null

    document.removeEventListener("mousemove", e => this.drag_move(e))
    document.removeEventListener("mouseup", e => this.drag_end(e))
  }

  drag_move(e) {
    if (this.drag == null) return

    const rect = this.e.getBoundingClientRect()
    const max_x = Math.floor(window.innerWidth - rect.width)
    const max_y = Math.floor(window.innerHeight - rect.height)

    const new_x = Math.min(Math.max(e.pageX - this.drag[0], 0), max_x)
    const new_y = Math.min(Math.max(e.pageY - this.drag[1], 0), max_y)

    this.e.style.left = `${new_x}px`
    this.e.style.top = `${new_y}px`
    this.e.style.position = "absolute"
    this.e.style.transform = ""
  }

  add_title(title) {
    const label = create_element(this.header, "span", "window-title")
    label.textContent = title
  }

  create_tab(title) {
    const tab = document.createElement("div")
    tab.style.overflow = "hidden"

    tab.button = create_element(this.header, "button", "window-tab-button")
    tab.button.textContent = title
    tab.button.addEventListener("click", () => {
      if (tab != this.selected_tab) {
        this.selected_tab.style.width = "0"
        this.selected_tab.style.height = "0"
        this.selected_tab.button.style.color = "rgb(0, 0, 0)"
        tab.style.width = "100%"
        tab.style.height = "100%"
        tab.button.style.color = "unset"
        this.selected_tab = tab
      }
    })

    this.tabs.push(tab)

    this.appendChild(tab)

    if (!this.selected_tab) {
      this.selected_tab = tab
      tab.style.height = "100%"
      tab.style.width = "100%"
    } else {
      tab.style.height = "0"
      tab.style.width = "0"
      tab.button.style.color = "rgb(0, 0, 0)"
    }

    return tab
  }

  get_body() {
    if (this.e.body == "undefined" || this.e.body == null) {
      const body_outer = create_element(this.e, "div")
      body_outer.style.overflow = "auto"
      body_outer.style.display = "flex"
      if (this.header.children.length > 0)
        body_outer.style.borderTop = "1px solid rgb(0, 0, 0)"
      this.e.body = create_element(body_outer, "div", "window-content")
    }

    return this.e.body
  }

  appendChild(child) {
    this.get_body().appendChild(child)
  }

  close() {
    const e = (this.outer || this.e)
    if (e.parentElement != null) e.parentElement.removeChild(e)
  }
}

class Modal extends Window {
  constructor(opts) {
    opts.modal = true
    super(opts)
  }
}

function create_window(title, opts) {
  if (document.windows == undefined) {
    document.windows = {}
  }

  if (document.windows[title]) return document.windows[title]

  opts.title = title
  document.windows[title] = new Window(opts)
  return document.windows[title]
}

export default Window
export { Modal, create_window }