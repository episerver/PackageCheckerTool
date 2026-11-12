/* Generated — do not edit. A correct store-only ZIP writer for .pptx/.docx/.xlsx.
   Usage: OptiZip.file([{ name: 'ppt/theme/theme1.xml', data: '<xml…>' }, …]) -> Blob */
(function () {
  var TABLE = (function () {
    var t = [], c, n, k;
    for (n = 0; n < 256; n++) {
      c = n;
      for (k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c >>> 0;
    }
    return t;
  })();

  function crc32(bytes) {
    var c = 0xFFFFFFFF;
    for (var i = 0; i < bytes.length; i++) c = TABLE[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
    return (c ^ 0xFFFFFFFF) >>> 0;
  }

  var enc = new TextEncoder();
  var bytesOf = function (d) { return typeof d === 'string' ? enc.encode(d) : new Uint8Array(d); };

  // A LOCAL header is 30 bytes and carries ONE version field; the CENTRAL directory entry is 46
  // and carries two. Mixing them up shifts the name and every offset after it.
  function localHeader(nameLen, crc, size) {
    var h = new DataView(new ArrayBuffer(30));
    h.setUint32(0, 0x04034b50, true);
    h.setUint16(4, 20, true);   // version needed
    h.setUint16(6, 0, true);    // flags
    h.setUint16(8, 0, true);    // method 0 = store
    h.setUint16(10, 0, true);   // mod time
    h.setUint16(12, 0x21, true); // mod date (1980-01-01; a fixed date keeps output reproducible)
    h.setUint32(14, crc, true);
    h.setUint32(18, size, true); // compressed
    h.setUint32(22, size, true); // uncompressed — equal, because we store
    h.setUint16(26, nameLen, true);
    h.setUint16(28, 0, true);   // extra length
    return new Uint8Array(h.buffer);
  }

  function centralEntry(nameLen, crc, size, offset) {
    var h = new DataView(new ArrayBuffer(46));
    h.setUint32(0, 0x02014b50, true);
    h.setUint16(4, 20, true);   // version made by
    h.setUint16(6, 20, true);   // version needed
    h.setUint16(8, 0, true);
    h.setUint16(10, 0, true);
    h.setUint16(12, 0, true);
    h.setUint16(14, 0x21, true);
    h.setUint32(16, crc, true);
    h.setUint32(20, size, true);
    h.setUint32(24, size, true);
    h.setUint16(28, nameLen, true);
    h.setUint16(30, 0, true);   // extra
    h.setUint16(32, 0, true);   // comment
    h.setUint16(34, 0, true);   // disk
    h.setUint16(36, 0, true);   // internal attrs
    h.setUint32(38, 0, true);   // external attrs
    h.setUint32(42, offset, true);
    return new Uint8Array(h.buffer);
  }

  function file(entries, mime) {
    var parts = [], central = [], offset = 0, n = 0;
    entries.forEach(function (e) {
      var name = enc.encode(e.name);
      var data = bytesOf(e.data);
      var crc = crc32(data);
      parts.push(localHeader(name.length, crc, data.length), name, data);
      central.push(centralEntry(name.length, crc, data.length, offset), name);
      offset += 30 + name.length + data.length;
      n++;
    });
    var cdSize = central.reduce(function (a, p) { return a + p.length; }, 0);
    var end = new DataView(new ArrayBuffer(22));
    end.setUint32(0, 0x06054b50, true);
    end.setUint16(4, 0, true);
    end.setUint16(6, 0, true);
    end.setUint16(8, n, true);
    end.setUint16(10, n, true);
    end.setUint32(12, cdSize, true);
    end.setUint32(16, offset, true);
    end.setUint16(20, 0, true);
    return new Blob(parts.concat(central, [new Uint8Array(end.buffer)]), {
      type: mime || 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    });
  }

  function download(entries, filename, mime) {
    var url = URL.createObjectURL(file(entries, mime));
    var a = document.createElement('a');
    a.href = url; a.download = filename;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }

  // ── Slides from CONTENT, so the model never hand-writes OOXML ──────────────────
  // ⛔ The same defect appeared one layer down: a generated deck had '<a:solidFill>' opened and
  // closed as '</p:spPr>', and a 150,000pt font ('sz="15000000"'). Both render nothing and both
  // come from writing OOXML by hand. Callers pass { title, bullets }; this emits the parts.
  // Colours come from '<a:schemeClr>' slots, so the deck inherits whatever theme is shipped —
  // that is what keeps it on brand without naming a single hex here.
  var esc = function (s) {
    return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  };
  var XMLD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
  var W = 12192000, H = 6858000; // 16:9 in EMU

  function textBox(id, name, x, y, cx, cy, runs) {
    return '<p:sp><p:nvSpPr><p:cNvPr id="' + id + '" name="' + esc(name) + '"/><p:cNvSpPr txBox="1"/>'
      + '<p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="' + x + '" y="' + y + '"/>'
      + '<a:ext cx="' + cx + '" cy="' + cy + '"/></a:xfrm>'
      + '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>'
      + '<p:txBody><a:bodyPr wrap="square"><a:normAutofit/></a:bodyPr><a:lstStyle/>' + runs + '</p:txBody></p:sp>';
  }

  // Written out in full rather than assembled with a conditional inside the tag: the first
  // version of this emitted an unclosed <a:pPr>, which is the same defect it exists to prevent.
  function para(text, sizePt, bold, schemeColour, bullet) {
    var pPr = bullet
      ? '<a:pPr marL="285750" indent="-285750"><a:buChar char="-"/></a:pPr>'
      : '<a:pPr marL="0" indent="0"><a:buNone/></a:pPr>';
    var rPr = '<a:rPr lang="en-US" sz="' + Math.round(sizePt * 100) + '"'
      + (bold ? ' b="1"' : '') + ' dirty="0">'
      + '<a:solidFill><a:schemeClr val="' + schemeColour + '"/></a:solidFill>'
      + '</a:rPr>';
    return '<a:p>' + pPr + '<a:r>' + rPr + '<a:t>' + esc(text) + '</a:t></a:r></a:p>';
  }

  // A filled rectangle: the accent rule under a title.
  function rect(id, x, y, cx, cy, schemeColour) {
    return '<p:sp><p:nvSpPr><p:cNvPr id="' + id + '" name="Accent"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
      + '<p:spPr><a:xfrm><a:off x="' + x + '" y="' + y + '"/><a:ext cx="' + cx + '" cy="' + cy + '"/></a:xfrm>'
      + '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
      + '<a:solidFill><a:schemeClr val="' + schemeColour + '"/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr>'
      + '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang="en-US"/></a:p></p:txBody></p:sp>';
  }

  // ⚠️ Every colour is a THEME slot, never a hex. A lead slide flips its background to the brand
  // dark and its ink to the light slot, so re-theming re-brands rather than leaving white on white.
  var M = 838200;
  function slideXml(s, index) {
    var lead = s.lead === undefined ? index === 0 : !!s.lead;
    var ink = lead ? 'bg1' : 'tx1';
    var y = lead ? 2300000 : 760000;
    var body = '';
    if (s.eyebrow) {
      body += textBox(10, 'Eyebrow', M, y - 520000, W - 2 * M, 400000,
        para(String(s.eyebrow).toUpperCase(), 11, true, lead ? 'accent3' : 'accent1', false));
    }
    body += textBox(2, 'Title', M, y, W - 2 * M, 1500000,
      para(s.title || '', lead ? 40 : 30, true, ink, false));
    body += rect(4, M, y + 1560000, 1000000, 50800, lead ? 'accent3' : 'accent1');
    var bullets = (s.bullets || []).map(function (b) { return para(b, 17, false, ink, true); }).join('');
    if (bullets) body += textBox(3, 'Body', M, y + 1850000, W - 2 * M, 2500000, bullets);
    if (s.footer) {
      body += textBox(5, 'Footer', M, H - 760000, W - 2 * M, 400000,
        para(s.footer, 10, false, lead ? 'bg1' : 'tx2', false));
    }
    var bg = lead
      ? '<p:bg><p:bgPr><a:solidFill><a:schemeClr val="tx1"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>'
      : '';
    return XMLD + '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
      + ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
      + ' xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
      + '<p:cSld>' + bg + '<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
      + '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/>'
      + '<a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>' + body
      + '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>';
  }

  var REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  var PML = 'http://schemas.openxmlformats.org/presentationml/2006/main';

  function build(deck, themeXml) {
    var slides = (deck && deck.slides) || [];
    if (!slides.length) throw new Error('[OptiZip] a deck needs at least one slide');
    var parts = [];
    var sldIds = slides.map(function (_, i) {
      return '<p:sldId id="' + (256 + i) + '" r:id="rId' + (i + 2) + '"/>';
    }).join('');
    var presRels = slides.map(function (_, i) {
      return '<Relationship Id="rId' + (i + 2) + '" Type="' + REL + '/slide" Target="slides/slide' + (i + 1) + '.xml"/>';
    }).join('');

    parts.push({ name: '[Content_Types].xml', data: XMLD
      + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      + '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      + '<Default Extension="xml" ContentType="application/xml"/>'
      + '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
      + '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
      + '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
      + '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
      + slides.map(function (_, i) {
          return '<Override PartName="/ppt/slides/slide' + (i + 1) + '.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>';
        }).join('')
      + '</Types>' });

    parts.push({ name: '_rels/.rels', data: XMLD
      + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      + '<Relationship Id="rId1" Type="' + REL + '/officeDocument" Target="ppt/presentation.xml"/></Relationships>' });

    parts.push({ name: 'ppt/presentation.xml', data: XMLD
      + '<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="' + REL + '" xmlns:p="' + PML + '">'
      + '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
      + '<p:sldIdLst>' + sldIds + '</p:sldIdLst>'
      + '<p:sldSz cx="' + W + '" cy="' + H + '"/><p:notesSz cx="' + H + '" cy="' + W + '"/></p:presentation>' });

    parts.push({ name: 'ppt/_rels/presentation.xml.rels', data: XMLD
      + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      + '<Relationship Id="rId1" Type="' + REL + '/slideMaster" Target="slideMasters/slideMaster1.xml"/>'
      + presRels
      + '<Relationship Id="rId' + (slides.length + 2) + '" Type="' + REL + '/theme" Target="theme/theme1.xml"/></Relationships>' });

    var clrMap = '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2"'
      + ' accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>';
    parts.push({ name: 'ppt/slideMasters/slideMaster1.xml', data: XMLD
      + '<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="' + REL + '" xmlns:p="' + PML + '">'
      + '<p:cSld><p:bg><p:bgPr><a:solidFill><a:schemeClr val="bg1"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>'
      + '<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
      + '<p:grpSpPr/></p:spTree></p:cSld>' + clrMap
      + '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>' });
    parts.push({ name: 'ppt/slideMasters/_rels/slideMaster1.xml.rels', data: XMLD
      + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      + '<Relationship Id="rId1" Type="' + REL + '/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
      + '<Relationship Id="rId2" Type="' + REL + '/theme" Target="../theme/theme1.xml"/></Relationships>' });

    parts.push({ name: 'ppt/slideLayouts/slideLayout1.xml', data: XMLD
      + '<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="' + REL + '" xmlns:p="' + PML + '" type="blank" preserve="1">'
      + '<p:cSld name="Blank"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
      + '<p:grpSpPr/></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>' });
    parts.push({ name: 'ppt/slideLayouts/_rels/slideLayout1.xml.rels', data: XMLD
      + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      + '<Relationship Id="rId1" Type="' + REL + '/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>' });

    parts.push({ name: 'ppt/theme/theme1.xml', data: themeXml });

    slides.forEach(function (s, i) {
      parts.push({ name: 'ppt/slides/slide' + (i + 1) + '.xml', data: slideXml(s, i) });
      parts.push({ name: 'ppt/slides/_rels/slide' + (i + 1) + '.xml.rels', data: XMLD
        + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        + '<Relationship Id="rId1" Type="' + REL + '/slideLayout" Target="../slideLayouts/slideLayout1.xml"/></Relationships>' });
    });
    return parts;
  }

  window.OptiZip = { file: file, download: download, buildDeck: build, slideXml: slideXml };
})();
