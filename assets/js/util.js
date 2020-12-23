const bytes_map = ["B", "K", "M", "G"]

function n_bytes(bytes) {
  if (bytes / 1024 < 1) return [bytes, 0]
  let r = n_bytes(bytes / 1024)
  return [r[0], r[1] + 1]
}

function bytes_str(bytes) {
  const r = n_bytes(bytes)
  return `${r[0].toFixed(1)}${bytes_map[r[1]]}`
}

function create_element(root, type, classes = "") {
  const e = document.createElement(type)
  if (classes.length > 0) {
    for (const class_name of classes.split(" "))
      e.classList.toggle(class_name, true)
  }
  if (root)
    root.appendChild(e)
  return e
}

function create_field(label, root, element = "input", type = "", default_value = "", min = "", max = "", step = 1) {
  const field = create_element(root, "div", "modal-row")
  if (label.length > 0) {
    field.label = create_element(field, "label")
    field.label.htmlFor = `${label}_${counter()}`
    field.label.textContent = label
  }
  field.input = create_element(field, element)
  field.input.value = default_value
  field.input.min = min
  field.input.max = max
  if (element == "input")
    field.input.type = type
  field.input.step = step
  field.input.id = `${label}_${counter(true)}`

  if (type == "number") {
    field.input.classList.toggle("input_number", true)
  }

  if (type == "range") {
    field.input.classList.toggle("range", true)
    field.number = create_element(field, "span")
    field.number.textContent = field.input.value
    field.input.addEventListener("change", () => {
      field.number.textContent = field.input.value
    })
    field.input.addEventListener("input", () => {
      field.number.textContent = field.input.value
    })
  }

  return field
}

export { bytes_str, create_element, create_field }
