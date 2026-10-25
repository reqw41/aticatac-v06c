// items.asm: предметы комнаты — список дверей комнаты this_rooms_door_list (explode_item). Вывод не моделируется.
'use strict';
const { S } = require('./core');

function draw_items(M) {
  M.wr(S.this_rooms_door_count, 0);
  const room = M.rd(S.room_number);
  let p = M.rd16(S.room_bank_items_per_room + 2 * room);
  for (;;) {
    let ix = M.rd16(p); p += 2;
    if (!ix) return;
    let c = 0;
    if (M.rd(S.room_number) !== M.rd(ix + 1)) { ix += 8; c = 8; }
    explode_item(M, ix, c);
    M.bank(S.room_bank_config);              // draw_item выбирает банк предметов, цикл — снова комнат
  }
}

function explode_item(M, ix, c) {
  M.wr(S.item_offset, c);
  const hl = S.this_rooms_door_list + 8 * M.rd(S.this_rooms_door_count);
  M.wr(S.item_is_door, M.rd(ix + 7));
  const d = M.rd(ix);
  M.wr(hl, d);
  M.wr(hl + 1, M.rd(ix + 3) >> 1);
  M.wr(hl + 2, M.rd(ix + 4));
  M.wr(hl + 3, ix & 0xff); M.wr(hl + 4, ix >> 8);
  const rot = M.rd(ix + 5);
  M.bank(S.item_bank_config);
  const meta = M.rd16(S.item_bank_items + 2 * d);
  let e;
  if (rot & 0x40) {
    e = (M.rd(meta) << 2) & 0xff;
    M.wr(hl + 5, M.rd(meta + 1) >> 2);
    M.wr(hl + 6, e);
  } else {
    M.wr(hl + 5, M.rd(meta));
    e = M.rd(meta + 1);
    M.wr(hl + 6, e);
  }
  M.wr(hl + 7, M.rd(S.item_offset));
  M.wr(hl + 2, (M.rd(hl + 2) - e + 1) & 0xff);
  const save = d === M.rd(S.magic_door) ||
    (d !== S.item_barrel && d !== S.item_bookcase && d !== S.item_clock && M.rd(S.item_is_door));
  if (save) M.wr(S.this_rooms_door_count, (M.rd(S.this_rooms_door_count) + 1) & 0xff);
  M.bank(S.room_bank_config);
}

module.exports = { draw_items, explode_item };
