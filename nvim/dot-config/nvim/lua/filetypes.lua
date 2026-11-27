-- AOSP / AAOS / SDV Filetype & Treesitter Associations

vim.filetype.add({
  extension = {
    bp = "bzl",
    vsidl = "textproto",
    pbtx = "textproto",
    pbtxt = "textproto",
    textproto = "textproto",
    aidl = "aidl",
    rc = "sh",
    te = "conf",
  },
  filename = {
    ["Android.bp"] = "bzl",
    ["OWNERS"] = "conf",
    ["file_contexts"] = "conf",
    ["service_contexts"] = "conf",
    ["property_contexts"] = "conf",
    ["hwservice_contexts"] = "conf",
    ["vndservice_contexts"] = "conf",
    ["seapp_contexts"] = "conf",
  },
  pattern = {
    [".*/fstab%..*"] = "sh",
  },
})

pcall(vim.treesitter.language.register, "starlark", "bzl")
pcall(vim.treesitter.language.register, "java", "aidl")
