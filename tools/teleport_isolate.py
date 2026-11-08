import cv2, numpy as np, os, glob
root = r'C:/Users/KABUM/Desktop/TCG Project/TCG-Simulator-On-Godot/tools/shots/teleport_frames'
out = os.path.join(root, 'isolated')
os.makedirs(out, exist_ok=True)
for prefix in ('source', 'destination'):
    for p in sorted(glob.glob(os.path.join(root, f'{prefix}_[0-9][0-9][0-9].png'))):
        im = cv2.imread(p)
        if im is None:
            continue
        im = cv2.rotate(im, cv2.ROTATE_180)
        h, w = im.shape[:2]
        side = 1100
        x0 = max(0, (w - side) // 2)
        y0 = max(0, (h - side) // 2)
        crop = im[y0:y0 + side, x0:x0 + side]
        name = os.path.basename(p)
        cv2.imwrite(os.path.join(out, name), crop)

# Contact sheet of the destination build, every third frame.
files = sorted(glob.glob(os.path.join(out, 'destination_[0-9][0-9][0-9].png')))
files = files[::3]
if files and files[-1] != sorted(glob.glob(os.path.join(out, 'destination_[0-9][0-9][0-9].png')))[-1]:
    files.append(sorted(glob.glob(os.path.join(out, 'destination_[0-9][0-9][0-9].png')))[-1])
imgs = []
for i, p in enumerate(files):
    im = cv2.imread(p)
    im = cv2.resize(im, (360, 360), interpolation=cv2.INTER_AREA)
    n = os.path.basename(p).replace('destination_', '').replace('.png', '')
    cv2.putText(im, n, (8, 26), cv2.FONT_HERSHEY_SIMPLEX, 0.75, (0, 255, 0), 2, cv2.LINE_AA)
    imgs.append(im)
cols = 4
rows = []
for i in range(0, len(imgs), cols):
    row = imgs[i:i + cols]
    while len(row) < cols:
        row.append(np.zeros_like(imgs[0]))
    rows.append(np.hstack(row))
sheet = np.vstack(rows)
cv2.imwrite(os.path.join(out, 'destination_contact.png'), sheet)
print('wrote', len(files), 'contact frames', sheet.shape)
