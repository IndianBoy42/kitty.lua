local M = {}
M.open_window_as = {
  fullscreen = "fullscreen",
  maximized = "maximized",
  minimized = "minimized",
  normal = "normal",
}
M.split_location = {
  after = "after",
  before = "before",
  default = "default",
  first = "first",
  hsplit = "hsplit",
  last = "last",
  neighbor = "neighbor",
  split = "split",
  vsplit = "vsplit",
}
M.stdin_source = {
  alternate = "@alternate",
  alternate_scrollback = "@alternate_scrollback",
  first_cmd_output_on_screen = "@first_cmd_output_on_screen",
  last_cmd_output = "@last_cmd_output",
  last_visited_cmd_output = "@last_visited_cmd_output",
  screen = "@screen",
  screen_scrollback = "@screen_scrollback",
  selection = "@selection",
  none = "none",
}
M.launch_type = {
  window = "window",
  tab = "tab",
  os_window = "os-window",
  overlay = "overlay",
  overlay_main = "overlay-main",
  background = "background",
  clipboard = "clipboard",
  primary = "primary",
}
return M
