# Opus I field portrait checkpoint

All **196 Opus I field portraits** are present through **Wakka (1-216S)**. The 20 Summons use their printed cards.

**Gippal (1-101R)**, **Snow (1-194S)**, **Brother (1-197S)**, and **Baralai (1-200S)** use clean crops of their printed illustrations. Revisit these when matching standalone art turns up.

Save each portrait as `<card-code>.jpg` at 429 × 444 px. Keep the existing illustration and pose. Check same-name prints and standalone artwork for an exact match, and use matching source art to fill areas covered by the printed bands. The field renderer supplies the cost, name, power, and damage counter. Backups have a blank lower band.

For Final Fantasy Tactics, frame the figure from the head to roughly the waist or thighs. Give tall hats, distinctive weapons, and held props enough room to read at field size.

For Final Fantasy III standard units, center the head horizontally at eye level and place the eyes about 36% down the art window. Scale the original uniformly so the head is about 34% of the window width at eye level, measured across the head itself. Frame the figure through the upper legs and let tall hats or plumes extend past the top edge where needed.

Add each batch’s card IDs to `restored_ids` in `tests/flow_probe.gd` and check the framing with the `--field-card` option in `tools/shot.tscn`.
