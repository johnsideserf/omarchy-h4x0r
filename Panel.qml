import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar button + popout for the h4x0r script. The popout is deliberately dressed
// as a terminal: phosphor green on near-black, mono everywhere, a binary strip
// ticking along under the title. Everything it knows comes from
// `h4x0r --status --json`; everything it does is a detached `h4x0r` call.
Panel {
  id: root
  moduleName: "io.github.johnsideserf.h4x0r"
  // namespaced like every other plugin: a bare name on a shared bus collides
  ipcTarget: "io.github.johnsideserf.h4x0r"

  readonly property string bin: Quickshell.env("HOME") + "/.local/bin/h4x0r"
  // theme-native by default; "phosphor" opts into the classic green-on-black
  readonly property bool followTheme: setting("palette", "theme") !== "phosphor"
  property string palette: setting("palette", "theme")

  readonly property var paletteNames: ["theme", "phosphor", "amber", "ice", "crimson", "synthwave", "mono"]
  readonly property var paletteSwatches: ({
    "phosphor": "#00d75f", "amber": "#ffb000", "ice": "#4fd6ff",
    "crimson": "#e01040", "synthwave": "#f92aad", "mono": "#b8b8b8"
  })
  readonly property var paletteBlurbs: ({
    "theme": "following your Omarchy theme",
    "phosphor": "P1 CRT green, the classic",
    "amber": "P3 CRT amber, warmer and older",
    "ice": "cold blue, high contrast",
    "crimson": "red alert",
    "synthwave": "hot pink and cyan",
    "mono": "grey scale, Nostromo"
  })

  function swatchColor(name) {
    if (name === "theme") return bar ? bar.foreground : Color.foreground
    return paletteSwatches[name] || "#00d75f"
  }

  function cyclePalette(step) {
    var i = paletteNames.indexOf(palette)
    palette = paletteNames[(i < 0 ? 0 : i + step + paletteNames.length) % paletteNames.length]
  }
  readonly property int pollSeconds: Math.max(2, setting("pollSeconds", 6))

  // ---- palette -------------------------------------------------------------
  readonly property color phosphor: swatchColor(palette)
  readonly property bool usesTheme: palette === "theme"
  readonly property color phosphorDim: Qt.darker(phosphor, 1.8)
  readonly property color phosphorDeep: Qt.darker(phosphor, 3.4)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: live ? (usesTheme ? barForeground : phosphor)
                                             : Qt.darker(barForeground, 1.6)

  // ---- state from `h4x0r --status --json` ----------------------------------
  property bool live: false
  property string backend: ""
  property string sessionId: ""
  property int panes: 0
  property bool herdrOk: false
  property bool tmuxOk: false
  property string lastError: ""

  // ---- user choices in the popout -----------------------------------------
  property string target: setting("multiplexer", "auto")
  property string layout: setting("layout", "auto")
  property bool music: setting("music", true) === true

  property bool cursorActive: false
  property int cursorIndex: 0
  property string binaryStrip: ""

  readonly property var rows: {
    var r = ["engage"]
    if (live) r.push("disengage")
    r.push("layout-auto", "layout-grid", "layout-cinema", "layout-minimal")
    r.push("palette")
    r.push("mux-auto", "mux-herdr", "mux-tmux", "music")
    return r
  }
  readonly property string currentRow: rows[Math.max(0, Math.min(cursorIndex, rows.length - 1))]

  readonly property string statusLine: {
    if (lastError !== "") return lastError
    if (!live) return "STANDBY // NO SESSION"
    return "SESSION ACTIVE // " + panes + " PANES // " + backend.toUpperCase()
  }

  function setCursor(rowId) {
    var i = rows.indexOf(rowId)
    if (i < 0) return
    cursorActive = true
    cursorIndex = i
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy === 0) return
    cursorIndex = Math.max(0, Math.min(rows.length - 1, cursorIndex + dy))
  }

  function activateCursor() {
    var id = currentRow
    if (id === "engage") engage()
    else if (id === "disengage") disengage()
    else if (id === "music") music = !music
    else if (id === "palette") cyclePalette(1)
    else if (id.indexOf("mux-") === 0) target = id.substring(4)
    else if (id.indexOf("layout-") === 0) layout = id.substring(7)
  }

  function argv(extra) {
    var a = [bin, "--mux", target, "--layout", layout, "--theme", usesTheme ? "omarchy" : "green"]
    if (!music) a.push("--no-music")
    for (var i = 0; i < extra.length; i++) a.push(extra[i])
    return a
  }

  function engage() {
    // h4x0r focuses an existing session rather than rebuilding it
    Quickshell.execDetached(argv([]))
    settleTimer.restart()
    close()
  }

  function disengage() {
    Quickshell.execDetached([bin, "--mux", target, "--close"])
    settleTimer.restart()
  }

  function rebuild() {
    Quickshell.execDetached(argv(["--rebuild"]))
    settleTimer.restart()
    close()
  }

  function refresh() { if (!statusProc.running) statusProc.running = true }

  function applyStatus(text) {
    var raw = String(text || "").trim()
    if (raw === "") { live = false; return }
    try {
      var d = JSON.parse(raw)
      live = d.running === true
      backend = String(d.backend || "")
      sessionId = String(d.id || "")
      panes = Number(d.panes || 0)
      herdrOk = d.herdr === true
      tmuxOk = d.tmux === true
      lastError = ""
    } catch (e) {
      live = false
      lastError = "STATUS UNREADABLE"
    }
  }

  function rollStrip() {
    var s = ""
    for (var i = 0; i < 46; i++) s += (Math.random() < 0.5 ? "0" : "1")
    binaryStrip = s
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = 0
    refresh()
    rollStrip()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onTargetChanged: refresh()

  Process {
    id: statusProc
    command: [root.bin, "--status", "--json", "--mux", root.target]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStatus(text) }
    stderr: StdioCollector { waitForEnd: true }
  }

  // status exits non-zero when nothing is running, so poll on a timer rather
  // than trusting exit codes
  Timer {
    // closed, this only has to notice the icon changing state, and each poll
    // is a subprocess - so idle far more slowly than when the popout is open
    interval: root.opened ? root.pollSeconds * 1000 : 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // a build or teardown takes a moment to show up in --status
  Timer {
    id: settleTimer
    interval: 1500
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    interval: 130
    running: root.opened
    repeat: true
    onTriggered: root.rollStrip()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      // give the slot an explicit size: an icon Item that sizes itself from a
      // glyph collapses to nothing if the glyph is ever missing
      Item {
        implicitWidth: Style.font.icon
        implicitHeight: Style.font.icon
        width: Style.font.icon
        height: Style.font.icon

        Text {
          anchors.centerIn: parent
          text: "󰚌"
          color: root.barIconColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.engage()
      else if (buttonCode === Qt.MiddleButton) root.disengage()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(780))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var k = String(t).toLowerCase()
        if (k === "e") root.engage()
        else if (k === "d") root.disengage()
        else if (k === "r") root.rebuild()
        else if (k === "m") root.music = !root.music
        else if (k === "p") root.cyclePalette(1)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: column
        width: panelFlick.width
        spacing: Style.space(12)

        // ---- terminal header -------------------------------------------
        Rectangle {
          width: parent.width
          implicitHeight: headerCol.implicitHeight + Style.space(20)
          color: root.usesTheme ? "transparent" : Qt.rgba(0, 0, 0, 0.30)
          border.color: Qt.rgba(root.phosphor.r, root.phosphor.g, root.phosphor.b, 0.35)
          border.width: 1
          radius: Style.cornerRadius

          Column {
            id: headerCol
            anchors.centerIn: parent
            width: parent.width - Style.space(20)
            spacing: Style.space(4)

            Text {
              textFormat: Text.PlainText
              text: "H4X0R"
              color: root.phosphor
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.letterSpacing: Style.space(6)
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.statusLine
              color: root.lastError !== "" ? root.urgent : root.phosphorDim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.binaryStrip
              color: root.phosphorDeep
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              clip: true
              elide: Text.ElideRight
            }
          }
        }

        // ---- actions ----------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(6)

          ActionRow {
            rowId: "engage"
            glyph: ""
            title: root.live ? "FOCUS SESSION" : "ENGAGE"
            subtitle: root.live ? "jump to the running workspace"
                                : root.layout + " layout, " + root.target + " backend"
            width: parent.width
            onTriggered: root.engage()
          }

          ActionRow {
            rowId: "disengage"
            visible: root.live
            glyph: ""
            title: "DISENGAGE"
            subtitle: "tear down " + (root.sessionId === "" ? "the session" : root.sessionId)
            accent: root.urgent
            width: parent.width
            onTriggered: root.disengage()
          }
        }

        PanelSeparator { foreground: root.phosphor }

        // ---- layout -----------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "LAYOUT"
            foreground: root.phosphor
            fontFamily: root.fontFamily
          }

          ActionRow {
            rowId: "layout-auto"
            glyph: "󰛨"
            title: "AUTO"
            subtitle: "pick a layout that fits the window"
            selected: root.layout === "auto"
            width: parent.width
            onTriggered: root.layout = "auto"
          }

          ActionRow {
            rowId: "layout-grid"
            glyph: "󱂬"
            title: "GRID"
            subtitle: "12 panes, asymmetric - the full thing"
            selected: root.layout === "grid"
            width: parent.width
            onTriggered: root.layout = "grid"
          }

          ActionRow {
            rowId: "layout-cinema"
            glyph: "󰍲"
            title: "CINEMA"
            subtitle: "5 big panes, readable across a room"
            selected: root.layout === "cinema"
            width: parent.width
            onTriggered: root.layout = "cinema"
          }

          ActionRow {
            rowId: "layout-minimal"
            glyph: ""
            title: "MINIMAL"
            subtitle: "3 panes - the look, not the whole machine"
            selected: root.layout === "minimal"
            width: parent.width
            onTriggered: root.layout = "minimal"
          }
        }

        PanelSeparator { foreground: root.phosphor }

        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "PALETTE"
            foreground: root.phosphor
            fontFamily: root.fontFamily
          }

          CursorSurface {
            width: parent.width
            hasCursor: root.cursorActive && root.currentRow === "palette"
            foreground: root.phosphor
            implicitHeight: swatches.implicitHeight + Style.spacing.rowPaddingX

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: root.setCursor("palette")
            }

            Row {
              id: swatches
              anchors.centerIn: parent
              spacing: Style.space(10)

              Repeater {
                model: root.paletteNames

                // inverted triangles rather than dots - straight edges sit
                // better against the terminal chrome than circles do
                Canvas {
                  id: chip
                  required property string modelData
                  readonly property bool picked: root.palette === modelData
                  readonly property color fill: root.swatchColor(modelData)
                  readonly property color ring: root.phosphor

                  width: Style.space(22)
                  height: Style.space(19)
                  opacity: picked ? 1.0 : 0.5

                  onFillChanged: requestPaint()
                  onPickedChanged: requestPaint()
                  onRingChanged: requestPaint()

                  onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var inset = 1.5
                    ctx.beginPath()
                    ctx.moveTo(inset, inset)
                    ctx.lineTo(width - inset, inset)
                    ctx.lineTo(width / 2, height - inset)
                    ctx.closePath()
                    ctx.fillStyle = chip.fill
                    ctx.fill()
                    if (chip.picked) {
                      ctx.lineWidth = 2
                      ctx.strokeStyle = chip.ring
                      ctx.stroke()
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.setCursor("palette")
                    onClicked: root.palette = chip.modelData
                  }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.palette.toUpperCase() + " \u2014 " + (root.paletteBlurbs[root.palette] || "")
            color: root.phosphorDim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }

        PanelSeparator { foreground: root.phosphor }

        // ---- backend ----------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "TARGET"
            foreground: root.phosphor
            fontFamily: root.fontFamily
          }

          ActionRow {
            rowId: "mux-auto"
            glyph: "󰛨"
            title: "AUTO"
            subtitle: "prefer herdr, fall back to tmux"
            selected: root.target === "auto"
            width: parent.width
            onTriggered: root.target = "auto"
          }

          ActionRow {
            rowId: "mux-herdr"
            glyph: ""
            title: "HERDR"
            subtitle: root.herdrOk ? "server reachable" : "no server reachable"
            enabledRow: root.herdrOk
            selected: root.target === "herdr"
            width: parent.width
            onTriggered: root.target = "herdr"
          }

          ActionRow {
            rowId: "mux-tmux"
            glyph: "󰍹"
            title: "TMUX"
            subtitle: root.tmuxOk ? "session " + "h4x0r" : "not installed"
            enabledRow: root.tmuxOk
            selected: root.target === "tmux"
            width: parent.width
            onTriggered: root.target = "tmux"
          }
        }

        PanelSeparator { foreground: root.phosphor }

        // ---- options ----------------------------------------------------
        ActionRow {
          rowId: "music"
          glyph: "󰝚"
          title: "MUSIC"
          subtitle: root.music ? "cliamp visualiser in the bottom strip" : "third rain in the bottom strip"
          selected: root.music
          width: parent.width
          onTriggered: root.music = !root.music
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: "e engage   d disengage   r rebuild   m music   p palette"
          color: root.phosphorDeep
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }

        Item { width: 1; height: Style.space(2) }
      }
      }
    }
  }

  component ActionRow: CursorSurface {
    id: rowItem
    property string rowId: ""
    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property bool enabledRow: true
    property bool selected: false
    property color accent: root.phosphor
    signal triggered()

    hasCursor: root.cursorActive && root.currentRow === rowId && enabledRow
    foreground: accent
    opacity: enabledRow ? 1.0 : 0.35
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: rowItem.enabledRow ? Qt.PointingHandCursor : Qt.ArrowCursor
      enabled: rowItem.enabledRow
      onEntered: root.setCursor(rowItem.rowId)
      onClicked: rowItem.triggered()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: rowItem.glyph
        color: rowItem.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: rowContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: rowItem.title
          color: rowItem.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.letterSpacing: 1
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: rowItem.subtitle
          color: root.phosphorDim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: rowItem.selected
        text: "◉"
        color: rowItem.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }
}
