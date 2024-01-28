#import "@preview/polylux:0.3.1": *

#let theme = (
  accent: rgb("#0065BD"),
  text: rgb("#000000"),
)

#let ctu-theme(
  aspect-ratio: "4-3",
  footer: [],
  background: white,
  foreground: black,
  body
) = {
  set page(
    paper: "presentation-" + aspect-ratio,
    margin: 1em,
    header: none,
    footer: none,
    fill: background,
  )
  set text(
    fill: foreground,
    size: 24pt,
    font: "Technika"
  )
  show footnote.entry: set text(size: .6em)
  show heading.where(level: 2): set block(below: 2em)
  show heading.where(level: 1): set block(below: 1em)
  show heading: set text(fill: theme.accent)
  set outline(target: heading.where(level: 1), title: none, fill: none)
  show outline.entry: it => it.body
  show outline: it => block(inset: (x: 1em), it)

  set page(footer: 
  utils.polylux-progress( p => box(fill: theme.accent, width: p * 100%, height: 1em, outset: (left: 24pt, right: 24pt))
  ))

  body
}

#let master-slide(body) = {
  polylux-slide({
    image("./logo-cvut.svg", height: 3em)
    body
  })
}

#let centered-slide(body) = {
  master-slide(align(center + horizon, body))
}

#let title-slide(body) = {
  set heading(outlined: false)
  show heading: set block(above: 3em)
  set text(fill: theme.accent)
  centered-slide(body)
}

#let slide(body) = {
  master-slide({
    block(inset: (top: 1em, x: 2em), body)
  })
}

#let notes(body) = { pdfpc.speaker-note(body) }