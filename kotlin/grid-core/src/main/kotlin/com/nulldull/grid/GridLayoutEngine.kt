package com.nulldull.grid

/** A rectangle in layout pixels (CSS pixels on the web, dp on Android), relative to the canvas. */
public data class GridRect(val x: Double, val y: Double, val width: Double, val height: Double)

/** A visible node with its clamped cell frame and resolved pixel rectangle. */
public data class GridPlacedNode(
    val node: GridNode,
    /** The breakpoint frame (or base frame) after clamping to the layout bounds. */
    val cells: GridFrame,
    val rect: GridRect,
    /** True when the node is stacked by content flow rather than positioned by its frame. */
    val flowing: Boolean,
) {
    /** Flowing text is sized by its content, not its frame height. */
    val contentSized: Boolean get() = flowing && node is GridBuiltinNode && node.kind == GridNodeKind.Text
}

/** The resolved geometry of one page at one container width. Nodes are in paint order (later on top). */
public data class GridPageLayout(
    /** Active breakpoint id, or "base". */
    val breakpointId: String,
    val layout: GridLayout,
    val cellSize: Double,
    val columns: Int,
    val rows: Int,
    val canvasWidth: Double,
    val canvasHeight: Double,
    val flow: Boolean,
    val nodes: List<GridPlacedNode>,
) {
    val step: Double get() = cellSize + layout.gap
}

/** Resolved active layout: the base layout or a breakpoint. */
public data class GridActiveLayout(val layout: GridLayout, val breakpointId: String?)

/**
 * UI-independent port of the Grid geometry in `@nulldull/grid-core` (`gridLayoutAt`,
 * `gridFrame`, `gridBounds`) and `@nulldull/grid-react` (`gridCellSize` and the canvas,
 * node and content-flow placement of `GridRenderer`). Golden tests in
 * `fixtures/grid-renderer` hold it to the TypeScript output.
 */
public object GridLayoutEngine {
    /** `gridLayoutAt`: the breakpoint with the largest `minWidth <= width`, else the base layout. */
    public fun layoutAt(document: GridDocument, width: Double): GridActiveLayout {
        val bp = document.breakpoints.sortedByDescending { it.minWidth }.firstOrNull { it.minWidth <= width }
        return GridActiveLayout(bp?.layout ?: document.layout, bp?.id)
    }

    /** `gridBounds`: columns and rows available to frames. Omitted maxima use the 512-cell bound. */
    public fun bounds(layout: GridLayout): Pair<Int, Int> = Pair(
        if (layout.direction == GridDirection.Vertical) layout.columns else layout.maxColumns ?: 512,
        if (layout.direction == GridDirection.Horizontal) layout.rows else layout.maxRows ?: 512,
    )

    /** `gridFrame`: the breakpoint override (or base frame) clamped into the bounds. Stored frames never change. */
    public fun frame(node: GridNode, layout: GridLayout, breakpointId: String?): GridFrame {
        val f = breakpointId?.let { node.frames[it] } ?: node.frame
        val (columns, rows) = bounds(layout)
        val width = minOf(f.width, columns)
        val height = minOf(f.height, rows)
        return GridFrame(x = minOf(f.x, columns - width), y = minOf(f.y, rows - height), width = width, height = height)
    }

    /** `gridCellSize`: vertical grids shrink cells to fit the width (never below 8); horizontal grids keep `cellSize`. */
    public fun cellSize(layout: GridLayout, width: Double): Double =
        if (layout.direction == GridDirection.Vertical) {
            minOf(
                layout.cellSize.toDouble(),
                maxOf(8.0, (width - (layout.padding ?: 0) * 2 - layout.gap * (layout.columns - 1)) / layout.columns),
            )
        } else layout.cellSize.toDouble()

    /**
     * Lays out [document] for a container [width]. [measureText] returns the full height
     * (content, padding and border) of a flowing text node at the given outer width; it is
     * called once per flowing text node, in document order. Pass [layoutOverride] and
     * [breakpointId] to force a specific layout, like the React `layout` prop.
     */
    public fun layout(
        document: GridDocument,
        width: Double,
        layoutOverride: GridLayout? = null,
        breakpointId: String? = null,
        measureText: (GridBuiltinNode, Double) -> Double,
    ): GridPageLayout {
        val active = if (layoutOverride != null) GridActiveLayout(layoutOverride, breakpointId) else layoutAt(document, width)
        val layout = active.layout
        val frames = document.nodes.filter { !it.hidden }.map { it to frame(it, layout, active.breakpointId) }
        val (boundColumns, boundRows) = bounds(layout)
        val cell = cellSize(layout, width)
        val gap = layout.gap.toDouble()
        val step = cell + gap
        val padding = (layout.padding ?: 0).toDouble()
        val columns = if (layout.direction == GridDirection.Vertical) boundColumns
        else minOf(boundColumns, maxOf(1, frames.maxOfOrNull { it.second.x + it.second.width } ?: 1))
        val rows = if (layout.direction == GridDirection.Horizontal) boundRows
        else minOf(boundRows, maxOf(1, frames.maxOfOrNull { it.second.y + it.second.height } ?: 1))

        fun fixed(node: GridNode, f: GridFrame) = GridPlacedNode(
            node, f,
            GridRect(padding + f.x * step, padding + f.y * step, f.width * step - gap, f.height * step - gap),
            flowing = false,
        )

        val flowGap = layout.flowGap
        if (flowGap == null) {
            return GridPageLayout(
                breakpointId = active.breakpointId ?: "base", layout = layout, cellSize = cell, columns = columns, rows = rows,
                canvasWidth = columns * step - gap + padding * 2, canvasHeight = rows * step - gap + padding * 2,
                flow = false, nodes = frames.map { (n, f) -> fixed(n, f) },
            )
        }
        // Content flow: the canvas spans the container up to the authored maximum; flowing
        // nodes stack in document order separated by flowGap; ignoreFlow nodes keep frames.
        val maxWidth = columns * (layout.cellSize + gap) - gap + padding * 2
        val canvasWidth = minOf(width, maxWidth)
        val content = maxOf(0.0, canvasWidth - padding * 2)
        var cursor = 0.0
        var count = 0
        val placed = frames.map { (node, f) ->
            if (node.ignoreFlow == true) return@map fixed(node, f)
            val nodeWidth = maxOf(0.0, (content + gap) * (f.width.toDouble() / columns) - gap)
            val height = if (node is GridBuiltinNode && node.kind == GridNodeKind.Text) measureText(node, nodeWidth)
            else f.height * step - gap
            if (count++ > 0) cursor += flowGap
            val rect = GridRect(padding + (content + gap) * (f.x.toDouble() / columns), padding + cursor, nodeWidth, height)
            cursor += height
            GridPlacedNode(node, f, rect, flowing = true)
        }
        val minHeight = frames.filter { it.first.ignoreFlow == true }
            .maxOfOrNull { (_, f) -> (f.y + f.height) * step - gap + padding * 2 }?.coerceAtLeast(0.0) ?: 0.0
        return GridPageLayout(
            breakpointId = active.breakpointId ?: "base", layout = layout, cellSize = cell, columns = columns, rows = rows,
            canvasWidth = canvasWidth, canvasHeight = maxOf(minHeight, cursor + padding * 2), flow = true, nodes = placed,
        )
    }
}
