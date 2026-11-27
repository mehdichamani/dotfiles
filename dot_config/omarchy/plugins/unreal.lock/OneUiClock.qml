import QtQuick

Item {
  id: root

  property string timeText: "00:00"
  property real clockHeight: 248
  property color textColor: "#ffffff"

  readonly property real scaleFactor: clockHeight / 140.0
  readonly property real digitWidth: 94 * scaleFactor
  readonly property real colonWidth: 34 * scaleFactor
  readonly property real charGap: 14 * scaleFactor

  implicitWidth: (digitWidth * 4) + colonWidth + (charGap * 4)
  implicitHeight: clockHeight

  onTimeTextChanged: canvas.requestPaint()
  onTextColorChanged: canvas.requestPaint()
  onClockHeightChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true
    renderStrategy: Canvas.Cooperative

    function rgbaStr(c, alpha) {
      return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + alpha.toFixed(3) + ")"
    }

    function grad(ctx, x1, y1, x2, y2, a1, a2) {
      var g = ctx.createLinearGradient(x1, y1, x2, y2)
      g.addColorStop(0.0, rgbaStr(root.textColor, a1))
      g.addColorStop(1.0, rgbaStr(root.textColor, a2))
      return g
    }

    function grad3(ctx, x1, y1, x2, y2, a1, a2, a3) {
      var g = ctx.createLinearGradient(x1, y1, x2, y2)
      g.addColorStop(0.0, rgbaStr(root.textColor, a1))
      g.addColorStop(0.55, rgbaStr(root.textColor, a2))
      g.addColorStop(1.0, rgbaStr(root.textColor, a3))
      return g
    }

    function strokeSeg(ctx, lw, style, drawFn) {
      ctx.save()
      ctx.lineWidth = lw
      ctx.lineCap = "round"
      ctx.lineJoin = "round"
      ctx.strokeStyle = style
      ctx.beginPath()
      drawFn(ctx)
      ctx.stroke()
      ctx.restore()
    }

    function drawDigit(ctx, ch) {
      // Static One UI 3D folded-ribbon proportions (matches reference 11:26).
      var lw = 25
      var r = lw * 0.5
      var left = r + 4
      var right = 94 - r - 4
      var top = r + 4
      var bot = 140 - r - 4
      var cx = 47
      var cy = 70

      if (ch === "0") {
        strokeSeg(ctx, lw, grad3(ctx, left, top, right, bot, 0.22, 0.72, 1.0), function(c) {
          c.ellipse(left, top, right - left, bot - top)
        })
        strokeSeg(ctx, lw, grad(ctx, right, top + 10, cx, bot, 0.35, 1.0), function(c) {
          c.arc(cx, cy, (right - left) * 0.5, -Math.PI * 0.22, Math.PI * 0.58, false)
        })
      } else if (ch === "1") {
        var flagX = left + 2
        var flagY = top + 14
        var stemX = cx + 8
        // Top-left flag fading from bright tip into shadow behind stem
        strokeSeg(ctx, lw, grad(ctx, flagX, flagY, stemX, top + 2, 1.0, 0.22), function(c) {
          c.moveTo(flagX, flagY)
          c.quadraticCurveTo(flagX + 16, flagY + 2, stemX, top)
        })
        // Vertical stem: soft shadow at top, pure white at bottom
        strokeSeg(ctx, lw, grad3(ctx, stemX, top, stemX, bot, 0.35, 0.85, 1.0), function(c) {
          c.moveTo(stemX, top)
          c.lineTo(stemX, bot)
        })
      } else if (ch === "2") {
        // Upper arch + diagonal sweeping down-left
        strokeSeg(ctx, lw, grad3(ctx, left + 4, top + 16, left, bot, 0.96, 0.55, 0.22), function(c) {
          c.moveTo(left + 6, top + 16)
          c.bezierCurveTo(left + 14, top - 6, right + 2, top - 2, right, top + 26)
          c.bezierCurveTo(right, cy - 2, left + 16, cy + 16, left, bot)
        })
        // Crisp bright white horizontal base overlapping the diagonal
        strokeSeg(ctx, lw, grad(ctx, left, bot, right, bot, 0.88, 1.0), function(c) {
          c.moveTo(left, bot)
          c.lineTo(right, bot)
        })
      } else if (ch === "3") {
        strokeSeg(ctx, lw, grad(ctx, left + 4, top + 6, cx, cy, 0.92, 0.28), function(c) {
          c.moveTo(left + 6, top + 6)
          c.bezierCurveTo(cx + 14, top - 4, right, top + 10, right - 2, top + 28)
          c.bezierCurveTo(right - 2, cy - 6, cx + 8, cy, cx - 2, cy)
        })
        strokeSeg(ctx, lw, grad3(ctx, cx, cy, left + 4, bot, 0.55, 0.92, 1.0), function(c) {
          c.moveTo(cx - 2, cy)
          c.bezierCurveTo(right, cy, right + 2, bot - 12, right - 4, bot - 8)
          c.bezierCurveTo(cx + 12, bot + 4, left + 10, bot + 2, left + 4, bot - 10)
        })
      } else if (ch === "4") {
        var barY = cy + 18
        var stem4X = right - 8
        strokeSeg(ctx, lw, grad(ctx, stem4X - 6, top, right, barY, 0.95, 0.28), function(c) {
          c.moveTo(stem4X - 6, top)
          c.lineTo(left, barY)
          c.lineTo(right, barY)
        })
        strokeSeg(ctx, lw, grad3(ctx, stem4X, top, stem4X, bot, 0.45, 0.88, 1.0), function(c) {
          c.moveTo(stem4X, top)
          c.lineTo(stem4X, bot)
        })
      } else if (ch === "5") {
        strokeSeg(ctx, lw, grad(ctx, right, top, left, cy - 6, 0.95, 0.28), function(c) {
          c.moveTo(right - 4, top)
          c.lineTo(left + 4, top)
          c.lineTo(left + 2, cy - 6)
        })
        strokeSeg(ctx, lw, grad3(ctx, left, cy, left + 4, bot, 0.55, 0.92, 1.0), function(c) {
          c.moveTo(left + 2, cy - 6)
          c.bezierCurveTo(cx + 10, cy - 16, right + 2, cy + 6, right - 2, bot - 18)
          c.bezierCurveTo(right - 6, bot + 4, left + 12, bot + 4, left + 4, bot - 8)
        })
      } else if (ch === "6") {
        var loopTop = cy - 6
        var loopMid = cy + 28
        // Upper hook sweeping down into the left side of the loop
        strokeSeg(ctx, lw, grad3(ctx, right - 12, top, left, loopMid, 0.98, 0.65, 0.22), function(c) {
          c.moveTo(right - 12, top)
          c.bezierCurveTo(left + 12, top + 10, left, cy - 10, left, loopMid)
        })
        // Bottom loop: wraps around with bright lit bottom-right edge
        strokeSeg(ctx, lw, grad3(ctx, left, loopTop, right, bot, 0.24, 0.72, 1.0), function(c) {
          c.ellipse(left, loopTop, right - left, bot - loopTop)
        })
        // Crisp front highlight on the lower-right curve of the loop
        strokeSeg(ctx, lw, grad(ctx, left + 10, bot, right, loopMid, 0.98, 0.55), function(c) {
          c.moveTo(left + 10, bot - 4)
          c.bezierCurveTo(cx + 12, bot + 4, right + 2, bot - 8, right, loopMid - 4)
        })
      } else if (ch === "7") {
        strokeSeg(ctx, lw, grad(ctx, left, top, right, top, 0.95, 0.30), function(c) {
          c.moveTo(left, top)
          c.lineTo(right, top)
        })
        strokeSeg(ctx, lw, grad3(ctx, right, top, cx - 10, bot, 0.55, 0.88, 1.0), function(c) {
          c.moveTo(right, top)
          c.quadraticCurveTo(right - 16, cy, cx - 10, bot)
        })
      } else if (ch === "8") {
        var rTop = 26
        var rBot = 30
        strokeSeg(ctx, lw, grad(ctx, cx, top, cx, cy, 0.92, 0.25), function(c) {
          c.ellipse(cx - rTop, top, rTop * 2, cy - top)
        })
        strokeSeg(ctx, lw, grad3(ctx, cx, cy, cx, bot, 0.45, 0.88, 1.0), function(c) {
          c.ellipse(cx - rBot, cy, rBot * 2, bot - cy)
        })
      } else if (ch === "9") {
        var r9 = (right - left) * 0.5
        var c9y = top + r9
        strokeSeg(ctx, lw, grad(ctx, left, c9y, right, c9y, 0.94, 0.24), function(c) {
          c.ellipse(left, top, right - left, (right - left) * 0.95)
        })
        strokeSeg(ctx, lw, grad3(ctx, right, c9y, left + 12, bot, 0.45, 0.88, 1.0), function(c) {
          c.moveTo(right, c9y)
          c.bezierCurveTo(right, bot - 10, cx + 6, bot + 4, left + 12, bot)
        })
      }
    }

    function drawColon(ctx) {
      var dotR = 11
      ctx.save()
      ctx.fillStyle = rgbaStr(root.textColor, 0.96)
      ctx.beginPath()
      ctx.arc(17, 50, dotR, 0, Math.PI * 2)
      ctx.fill()
      ctx.beginPath()
      ctx.arc(17, 94, dotR, 0, Math.PI * 2)
      ctx.fill()
      ctx.restore()
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.clearRect(0, 0, width, height)

      var s = root.scaleFactor
      var x = 0
      var text = root.timeText || "00:00"
      for (var i = 0; i < text.length; i++) {
        var ch = text.charAt(i)
        ctx.save()
        ctx.translate(x, 0)
        ctx.scale(s, s)
        if (ch === ":") {
          drawColon(ctx)
          x += root.colonWidth + root.charGap
        } else {
          drawDigit(ctx, ch)
          x += root.digitWidth + root.charGap
        }
        ctx.restore()
      }
    }
  }
}
