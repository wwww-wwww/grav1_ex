class Modal {
  constructor({root=null, can_close=true, title=null}={}) {
    this.root = root || document.querySelector("body")
    this.tabs = []
    this.selected_tab = null

    this.e = document.createElement("div")
    this.e.className = "modal"

    this.back = document.createElement("div")
    this.back.className = "modal-back"
    this.e.appendChild(this.back)

    this.e.inner = document.createElement("div")
    this.e.inner.className = "modal-inner"
    this.e.appendChild(this.e.inner)

    const top = document.createElement("div")
    top.className = "modal-top"
    this.e.inner.appendChild(top)

    this.header = document.createElement("div")
    this.header.className = "modal-header"
    top.appendChild(this.header)
    
    if (can_close) {
      this.back.addEventListener("click", _ => this.close())

      const modal_close = document.createElement("button")
      modal_close.className = "modal-close square material-icons"
      modal_close.textContent = "close"
      modal_close.addEventListener("click", _ => this.close())
      top.appendChild(modal_close)
    }

    if (title) {
      this.add_title(title)
    }
  }

  show() {
    this.root.appendChild(this.e)
  }

  add_title(title) {
    const label = document.createElement("span")
    label.className = "modal-title"
    label.textContent = title
    this.header.appendChild(label)
  }

  create_tab(title) {
    const tab = document.createElement("div")
    tab.style.overflow = "hidden"

    tab.button = document.createElement("button")
    tab.button.className = "modal-tab-button"
    tab.button.textContent = title
    this.header.appendChild(tab.button)

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
      const body_outer = document.createElement("div")
      body_outer.style.overflow = "auto"
      body_outer.style.display = "flex"
      if (this.header.children.length > 0)
        body_outer.style.borderTop = "1px solid rgb(0, 0, 0)"
      this.e.inner.appendChild(body_outer)
      this.e.body = document.createElement("div")
      this.e.body.className = "modal-content"
      body_outer.appendChild(this.e.body)
    }
  
    return this.e.body
  }

  appendChild(child) {
    this.get_body().appendChild(child)
  }

  close() {
    this.root.removeChild(this.e)
  }

}

export default Modal
