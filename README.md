# Cinnamon BBCWX Weathertext Fix

Portable repair script for the Cinnamon Spices `bbcwx@oak-wood.co.uk` Weather desklet, version `5.4`.

This fixes the vertical-layout weather text by applying a zoom-scaled maximum width and enabling word-aware line wrapping. It is intended for Cinnamon systems where the desklet's local JavaScript may be replaced by a desklet refresh or update.

## The code fix

In a stock BBCWX 5.4 installation, look around line 709 for this original one-line code:

```javascript
if (this.weathertext) this.weathertext.style= 'text-align : center; font-size:'+BBCWX_CC_TEXT_SIZE*this.zoom+'px';
```

Replace that line with the following block:

```javascript
if (this.weathertext) {
  this.weathertext.style = 'text-align: center; font-size:' + BBCWX_CC_TEXT_SIZE * this.zoom + 'px; max-width:' + (170 * this.zoom) + 'px;';
  this.weathertext.clutter_text.set_line_wrap(true);
  this.weathertext.clutter_text.set_line_wrap_mode(imports.gi.Pango.WrapMode.WORD_CHAR);
}
```

The important part is the zoom-aware width:

```javascript
max-width: 170 * this.zoom
```

The script recognizes that original one-line form, applies the replacement automatically, and removes the known duplicate `if (this.weathertext)` variant when it is present. Line numbers can vary slightly between desklet revisions, so search for `this.weathertext.style` if it is not exactly on line 709.

## Usage

Download the script, make it executable, and run it:

```bash
chmod +x repair-bbcwx-weathertext.sh
./repair-bbcwx-weathertext.sh
```

If the desklet is installed system-wide and the script reports a permission error:

```bash
sudo ./repair-bbcwx-weathertext.sh
```

After a successful repair, reload all desklets from the Cinnamon desktop context menu.

## What the script does

- Checks the user's `~/.local/share/cinnamon/desklets` copy first.
- Falls back to `/usr/share/cinnamon/desklets` if no user-local 5.4 copy exists.
- Operates only on `bbcwx@oak-wood.co.uk/5.4/desklet.js`.
- Creates a timestamped `desklet.js.BEFORE-REPAIR-*` backup before changing anything.
- Uses an atomic replacement after the repaired file is prepared.
- Does nothing on a second run when the file is already repaired.
- Never inspects or modifies the 3.0 desklet.
