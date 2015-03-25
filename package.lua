return {
  name = "virgo-agent-toolkit/virgo",
  version = "0.11.5",
  dependencies = {
    "luvit/luvit@2.0.3",
    "rphillips/async@0.0.2",
    "rphillips/hsm@0.0.2",
    "rphillips/line-emitter@0.3.3",
    "rphillips/logging@0.1.3",
    "virgo-agent-toolkit/split-stream@0.5.3",
    "virgo-agent-toolkit/request@0.2.3",
  },
  files = {
    "**.lua",
    "!lit*",
    "!test*"
  }
}
