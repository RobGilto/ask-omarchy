import QtQuick
import Quickshell.Io

// One question in flight, and the conversation it belongs to.
//
// The knowledge work all lives in `omarchy-ask`; this is a reader for the
// stream-json it prints, the same way Agent.qml is a reader for the usage
// records. Every line is one JSON event: text deltas append to `answer`, the
// init event names the session so a follow-up can resume it.
Item {
  id: root
  visible: false

  property string model: "sonnet"
  property string reviewModel: "opus"
  property bool keepSession: true

  property string answer: ""
  property string error: ""
  property string sessionId: ""
  property string question: ""
  readonly property bool running: proc.running
  // The first delta is what turns "thinking" into "answering", and it is the
  // only honest signal that the model is actually producing something.
  readonly property bool streaming: proc.running && answer !== ""

  readonly property bool teaching: teachProc.running

  signal finished()
  signal taught()

  function send(text) {
    var q = String(text || "").trim()
    if (q === "" || proc.running) return
    root.question = q
    root.answer = ""
    root.error = ""

    var args = ["omarchy-ask", "--stream", "--model", root.model]
    if (root.keepSession && root.sessionId !== "")
      args = args.concat(["--session", root.sessionId])
    args.push(q)

    proc.command = args
    proc.running = true
  }

  // Teaching writes to the corrections file and nothing else; the next question
  // picks it up because omarchy-ask reads that file on every fresh turn.
  function teach(correction) {
    var right = String(correction || "").trim()
    if (right === "" || teachProc.running) return
    // The first line is the claim the model made; the rest is elaboration that
    // would only make the correction harder to read later.
    var wrong = String(root.answer).split("\n").filter(function(l) { return l.trim() !== "" })[0] || ""
    if (wrong.length > 200) wrong = wrong.substring(0, 197) + "..."

    teachProc.command = ["omarchy-ask", "teach",
                         "--question", root.question,
                         "--wrong", wrong,
                         "--right", right]
    teachProc.running = true
  }

  // A second opinion is a conversation, not a one-shot: this hands the question
  // and the answer to an interactive Claude in a terminal, where it can run
  // hyprctl, read the sources, and record its own correction.
  function review() {
    if (root.question === "" || reviewProc.running) return
    reviewProc.command = ["omarchy-launch-tui", "--app-id=org.omarchy.ask-review",
                          "omarchy-ask", "review",
                          "--question", root.question,
                          "--answer", root.answer,
                          "--model", root.reviewModel]
    reviewProc.running = true
  }

  function cancel() {
    if (proc.running) proc.running = false
  }

  // A new conversation, not just a cleared screen: dropping the session id is
  // what stops the next question from being read as a follow-up.
  function reset() {
    cancel()
    root.sessionId = ""
    root.answer = ""
    root.error = ""
    root.question = ""
  }

  function handleLine(line) {
    var event
    try {
      event = JSON.parse(String(line))
    } catch (e) {
      return // not JSON: a tool banner the CLI failed to filter
    }
    if (!event || typeof event !== "object") return

    if (event.type === "system" && event.subtype === "init") {
      if (event.session_id) root.sessionId = event.session_id
    } else if (event.type === "stream_event" && event.event
               && event.event.type === "content_block_delta"
               && event.event.delta && event.event.delta.type === "text_delta") {
      root.answer += event.event.delta.text
    } else if (event.type === "result") {
      if (event.session_id) root.sessionId = event.session_id
      if (event.is_error) root.error = String(event.result || "the model returned an error")
      // A turn that produced no deltas still has its text in the result.
      if (root.answer === "" && !event.is_error && event.result) root.answer = String(event.result)
    }
  }

  Process {
    id: reviewProc
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) root.error = "could not open a terminal for the review"
    }
  }

  Process {
    id: teachProc
    stderr: SplitParser {
      onRead: function(line) {
        var text = String(line).trim()
        if (text.indexOf("omarchy-ask: ") === 0 && text.indexOf("recorded") < 0)
          root.error = text.substring(13)
      }
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode === 0) root.taught()
      else if (root.error === "") root.error = "could not record the correction"
    }
  }

  Process {
    id: proc

    stdout: SplitParser {
      onRead: function(line) { root.handleLine(line) }
    }

    // omarchy-ask puts its own diagnostics here; the last one is the useful one.
    stderr: SplitParser {
      onRead: function(line) {
        var text = String(line).trim()
        if (text !== "" && text.indexOf("omarchy-ask: ") === 0)
          root.error = text.substring(13)
      }
    }

    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0 && root.error === "" && root.answer === "")
        root.error = "omarchy-ask exited " + exitCode
      root.finished()
    }
  }
}
