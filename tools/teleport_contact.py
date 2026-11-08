import cv2, numpy as np, os
root = r'C:/Users/KABUM/Desktop/TCG Project/TCG-Simulator-On-Godot/tools/shots/teleport_frames'
nums = [0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 36, 42, 48, 54, 57]
imgs = []
for n in nums:
    p = f'{root}/destination_{n:03d}.png'
    im = cv2.imread(p)
    if im is None:
        continue
    im = cv2.resize(im, (480, 270), interpolation=cv2.INTER_AREA)
    cv2.putText(im, str(n), (8, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2, cv2.LINE_AA)
    imgs.append(im)
rows = []
for i in range(0, len(imgs), 4):
    row = imgs[i:i+4]
    while len(row) < 4:
        row.append(np.zeros_like(imgs[0]))
    rows.append(np.hstack(row))
sheet = np.vstack(rows)
cv2.imwrite(f'{root}/destination_contact.png', sheet)
print('wrote', sheet.shape, 'frames', len(imgs))
