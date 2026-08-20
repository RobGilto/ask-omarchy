import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "ask-omarchy.ask"
  ipcTarget: "ask-omarchy.ask"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The bar lays widgets out by implicit size; without this the button has a
  // zero-width slot and never appears, even though the panel behind it works.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Teaching reuses the one text field rather than opening a second one: the
  // correction is a reply to the answer on screen, and a separate box would
  // read as a separate conversation.
  property bool teachMode: false

  function submit() {
    var text = String(input.text).trim()
    if (text === "" || runner.running) return
    if (teachMode) {
      runner.teach(text)
      teachMode = false
    } else {
      runner.send(text)
    }
    input.text = ""
  }

  function startTeaching() {
    if (runner.answer === "" || runner.running) return
    teachMode = true
    input.text = ""
    input.forceActiveFocus()
  }

  // Ask the same question again once the correction is on file, so the lesson
  // is visible immediately instead of on some later question.
  Connections {
    target: runner
    function onTaught() {
      var question = runner.question
      runner.reset()
      runner.send(question)
    }
  }

  function secondOpinion() {
    if (runner.question === "" || runner.running) return
    runner.review()
    root.close()
  }

  function newConversation() {
    runner.reset()
    teachMode = false
    input.text = ""
    input.forceActiveFocus()
  }

  // The field is the point of the panel — a popup that opens without a cursor
  // in it costs a click before every question.
  onOpenedChanged: {
    if (!opened) { runner.cancel(); teachMode = false }
  }

  Ask {
    id: runner
    model: root.setting("model", "sonnet")
    reviewModel: root.setting("reviewModel", "opus")
    keepSession: root.setting("keepSession", true)
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function reset(): string { root.newConversation(); return "ok" }
    function ask(question: string): string {
      root.open()
      runner.send(question)
      return "ok"
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰭹"
    active: runner.running
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) { root.newConversation(); root.open() }
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    // The field, not the key catcher: KeyboardPanel focuses this after the
    // surface maps, and a question box that opens without a cursor in it costs
    // a click before every question.
    focusTarget: input
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Documented escape hatch: with the field focused every key belongs to
      // it, including the j/k/r shortcuts this catcher would otherwise eat.
      blocked: input.activeFocus

      onCloseRequested: root.close()
      onActivateRequested: input.forceActiveFocus()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          answerFlick.contentY = Math.max(0, Math.min(answerFlick.contentY + dy * Style.space(48),
                                                      Math.max(0, answerFlick.contentHeight - answerFlick.height)))
      }
      onTextKey: function(t) {
        if (t === "t") root.startTeaching()
        else if (t === "o") root.secondOpinion()
        else if (t === "n") root.newConversation()
        else if (t === "i" || t === "/") input.forceActiveFocus()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        TextField {
          id: input
          width: parent.width
          foreground: root.foreground
          placeholderText: runner.running ? "…"
            : (root.teachMode ? "What is the correct answer?" : "Ask about Omarchy")
          enabled: !runner.running
          font.family: root.fontFamily
          onAccepted: root.submit()

          // Esc backs out one step at a time: clear a half-typed question,
          // hand the keys back to the panel, then close.
          Keys.onEscapePressed: function(event) {
            if (root.teachMode) { root.teachMode = false; input.text = "" }
            else if (input.text !== "") input.text = ""
            else keyCatcher.forceActiveFocus()
            event.accepted = true
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            id: status
            width: parent.width - modelLabel.width - Style.space(8)
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            color: runner.error !== "" ? root.urgent : root.dim
            text: {
              if (runner.error !== "") return runner.error
              if (root.teachMode) return "teaching · what should it have said?"
              if (runner.teaching) return "recording the correction…"
              if (runner.streaming) return "answering…"
              if (runner.running) return "thinking…"
              if (runner.question !== "") return runner.question
              return "Enter to ask · Esc clears, then closes"
            }
          }

          Text {
            id: modelLabel
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            color: root.dim
            text: runner.sessionId !== "" ? runner.model + " · follow-up" : runner.model
          }
        }

        Flickable {
          id: answerFlick
          width: parent.width
          height: Math.min(answer.implicitHeight, Style.space(430))
          contentWidth: width
          contentHeight: answer.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          // Follow the tail while text streams in, but stop fighting the user
          // once they scroll back up to re-read something.
          property bool pinned: true
          onContentYChanged: if (!runner.running) pinned = contentY >= contentHeight - height - Style.space(8)
          onContentHeightChanged: if (pinned) contentY = Math.max(0, contentHeight - height)

          Text {
            id: answer
            width: answerFlick.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            color: root.foreground
            // The first line is the answer; the CLI's system prompt guarantees it.
            text: runner.answer
          }
        }

        // Under the answer, because that is what it acts on: the button only
        // means anything once there is a claim on screen to correct.
        Row {
          width: parent.width
          spacing: Style.space(8)
          visible: runner.answer !== "" || runner.question !== ""

          Button {
            text: root.teachMode ? "Cancel" : "Teach"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            enabled: runner.answer !== "" && !runner.running && !runner.teaching
            tooltipText: root.teachMode
              ? "Leave the correction unwritten"
              : "Record what this should have said, then ask again"
            onClicked: root.teachMode ? (root.teachMode = false) : root.startTeaching()
          }

          Button {
            text: "2nd opinion"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            enabled: runner.answer !== "" && !runner.running
            tooltipText: "Open a terminal and have " + runner.reviewModel + " check this answer"
            onClicked: root.secondOpinion()
          }

          Button {
            text: "New"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            enabled: !runner.running
            tooltipText: "Forget this conversation and start over"
            onClicked: root.newConversation()
          }
        }
      }
    }
  }
}
