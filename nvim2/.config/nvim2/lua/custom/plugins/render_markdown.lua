require('render-markdown').setup {
  file_types = { 'markdown' },
  heading = { sign = false, position = 'overlay' },
  code = {
    language_icon = false,
    language_name = false,
    language_info = false,
    left_pad = 1,
    right_pad = 1,
    width = 'block',
    border = 'thin',
  },
  latex = { enabled = false },
}
