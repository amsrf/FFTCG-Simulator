import cv2, numpy as np, os
ref_root = r'C:/Users/KABUM/clip3_frames'
our_root = r'C:/Users/KABUM/Desktop/TCG Project/TCG-Simulator-On-Godot/tools/shots/teleport_frames/isolated'
pairs = [(41,0),(44,6),(48,12),(52,18),(56,24),(60,30),(64,36),(68,48),(72,56)]
rows=[]
for rn, on in pairs:
    ref=cv2.imread(f'{ref_root}/{rn:03d}.png')
    ref=ref[210:680,430:880]
    ref=cv2.resize(ref,(450,470),interpolation=cv2.INTER_AREA)
    our=cv2.imread(f'{our_root}/destination_{on:03d}.png')
    our=cv2.resize(our,(470,470),interpolation=cv2.INTER_AREA)
    cv2.putText(ref,f'REF {rn}',(8,28),cv2.FONT_HERSHEY_SIMPLEX,.8,(0,255,0),2,cv2.LINE_AA)
    cv2.putText(our,f'OURS {on}',(8,28),cv2.FONT_HERSHEY_SIMPLEX,.8,(0,255,0),2,cv2.LINE_AA)
    rows.append(np.hstack([ref,our]))
sheet=np.vstack(rows)
cv2.imwrite(r'C:/Users/KABUM/Desktop/TCG Project/TCG-Simulator-On-Godot/tools/shots/teleport_compare.png',sheet)
print('wrote',sheet.shape)
