ObjC.import('CoreGraphics');
var raw = $.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly, 0);
var list = ObjC.deepUnwrap(ObjC.castRefToObject(raw));
list.filter(function (w) { return w.kCGWindowLayer === 0; }).map(function (w) {
  var b = w.kCGWindowBounds;
  return [w.kCGWindowOwnerPID, w.kCGWindowOwnerName, b.X, b.Y, b.Width, b.Height].join('|');
}).join('\n');
