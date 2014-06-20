function drawGraph(id, data, labels, colors) {
  new Morris.Line({
    element: id,
    data: data,
    xkey: 'period',
    ykeys: labels,
    labels: labels,
    lineColors: colors,
    pointSize: 0
  });
}
