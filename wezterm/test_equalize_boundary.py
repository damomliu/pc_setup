# 回歸：水平均分不可對最左欄的外緣下刀。


def old_adjust_direction(axis, delta):
    if axis == 'width':
        return 'Right' if delta > 0 else 'Left'
    return 'Down' if delta > 0 else 'Up'


def new_adjust(axis, delta):
    """delta = desired_left - current_left。只移動左右/上下相接的那條邊。"""
    if delta > 0:
        return ('left', 'Right' if axis == 'width' else 'Down', delta)
    if delta < 0:
        return ('right', 'Left' if axis == 'width' else 'Up', -delta)
    return None


def test_shrink_first_column_does_not_hit_window_edge():
    # 視窗縮放過後常見：左欄過寬。舊邏輯對最左 pane 下 Left，等於打到視窗外緣。
    current = [100, 40, 40]
    total = sum(current)
    base = total // 3
    extra = total % 3
    desired0 = base + (1 if 0 < extra else 0)
    delta = desired0 - current[0]
    assert delta < 0
    assert old_adjust_direction('width', delta) == 'Left'
    side, direction, amount = new_adjust('width', delta)
    assert side == 'right'
    assert direction == 'Left'
    assert amount == -delta


def test_grow_first_column_still_moves_inner_edge():
    current = [20, 80, 80]
    total = sum(current)
    base = total // 3
    extra = total % 3
    desired0 = base + (1 if 0 < extra else 0)
    delta = desired0 - current[0]
    assert delta > 0
    side, direction, amount = new_adjust('width', delta)
    assert side == 'left'
    assert direction == 'Right'
    assert amount == delta


def partition_infos(infos, cut, pos_key, size_key, slack=1):
    before, after = [], []
    for info in infos:
        pos = info[pos_key]
        finish = pos + info[size_key]
        is_before = finish <= cut + slack
        is_after = pos >= cut - slack
        if is_before and is_after:
            (after if pos >= cut else before).append(info)
        elif is_before:
            before.append(info)
        elif is_after:
            after.append(info)
        else:
            return None
    if before and after:
        return before, after
    return None


def desired_from_window(window_cols, n_cols, mux_left, gutters=None):
    """過期 mux 加總不可當總寬；目標欄寬要用視窗實際欄數。"""
    if gutters is None:
        gutters = n_cols - 1
    total = window_cols - gutters
    base = total // n_cols
    return base - mux_left


def test_stale_wide_mux_equalize_matches_window_not_mux_sum():
    # tab mux 479（239+1+239），視窗實際 319。若用 mux 當總寬會 delta=0。
    mux_left, mux_right = 239, 239
    assert mux_left + 1 + mux_right == 479
    assert (mux_left + mux_right) // 2 == mux_left
    delta = desired_from_window(319, 2, mux_left)
    assert delta == -80
    painted_left = mux_left + delta
    painted_right = 319 - 1 - painted_left
    assert painted_left == painted_right == 159


def test_stale_narrow_left_grows_to_half_window():
    # 先前 75|403 的 mux 套到 319 欄視窗。
    delta = desired_from_window(319, 2, 75)
    assert delta == 84
    assert 75 + delta == 159
    assert 319 - 1 - 159 == 159


def cluster_groups(infos, pos_key, slack=1):
    sorted_infos = sorted(infos, key=lambda i: (i[pos_key], i['left']))
    groups = []
    for info in sorted_infos:
        if groups and abs(info[pos_key] - groups[-1]['pos']) <= slack:
            groups[-1]['panes'].append(info)
        else:
            groups.append({'pos': info[pos_key], 'panes': [info]})
    return groups


def target_content(mux_total, count, window_extent, slack=1):
    if window_extent and abs(mux_total + (count - 1) - window_extent) > slack:
        return max(1, window_extent - (count - 1))
    return mux_total


def test_grid_misaligned_is_two_rows_not_three_columns():
    # 使用者量到的 tab4：上 14/2543、下 850/1705。
    panes = [
        {'name': 'TL', 'left': 0, 'width': 1, 'top': 0, 'height': 34},
        {'name': 'TR', 'left': 2, 'width': 317, 'top': 0, 'height': 34},
        {'name': 'BL', 'left': 0, 'width': 106, 'top': 35, 'height': 17},
        {'name': 'BR', 'left': 107, 'width': 212, 'top': 35, 'height': 17},
    ]
    by_left = cluster_groups(panes, 'left')
    assert len(by_left) == 3
    rows = cluster_groups(panes, 'top')
    assert len(rows) == 2
    assert [p['name'] for p in rows[0]['panes']] == ['TL', 'TR']
    assert [p['name'] for p in rows[1]['panes']] == ['BL', 'BR']
    top_total = sum(p['width'] for p in rows[0]['panes'])
    assert target_content(top_total, 2, 319) == top_total
    assert 1 + (top_total // 2 - 1) == 159


def test_window_usable_only_when_mux_disagrees():
    assert target_content(318, 2, 319) == 318
    assert target_content(478, 2, 319) == 318


def ranges_overlap_exclusive(start_a, size_a, start_b, size_b):
    return min(start_a + size_a, start_b + size_b) - max(start_a, start_b) > 0


def expand_band(infos, band_pos, band_span, pos_key, size_key):
    return [
        info for info in infos
        if ranges_overlap_exclusive(band_pos, band_span, info[pos_key], info[size_key])
    ]


def test_tab3_spanning_left_is_in_both_width_rows():
    # 左欄通高 + 右邊 3x2。舊邏輯下列只有 3 欄、用整窗 319 去均。
    panes = [
        {'name': 'CCaption', 'left': 0, 'width': 79, 'top': 0, 'height': 52},
        {'name': 'LanePLC', 'left': 80, 'width': 106, 'top': 0, 'height': 25},
        {'name': 'Tower1', 'left': 187, 'width': 106, 'top': 0, 'height': 26},
        {'name': 'CardR', 'left': 294, 'width': 25, 'top': 0, 'height': 26},
        {'name': 'pwsh', 'left': 80, 'width': 106, 'top': 26, 'height': 26},
        {'name': 'Tower2', 'left': 187, 'width': 106, 'top': 27, 'height': 25},
        {'name': 'RemoteC', 'left': 294, 'width': 25, 'top': 27, 'height': 25},
    ]
    rows = cluster_groups(panes, 'top')
    top = rows[0]
    top_span = min(p['height'] for p in top['panes'])
    top_band = expand_band(panes, top['pos'], top_span, 'top', 'height')
    assert sorted(p['name'] for p in top_band) == ['CCaption', 'CardR', 'LanePLC', 'Tower1']
    assert target_content(sum(p['width'] for p in top_band), 4, 319) == 316
    assert 316 // 4 == 79

    bot = rows[1]
    bot_span = min(p['height'] for p in bot['panes'])
    bot_band = expand_band(panes, bot['pos'], bot_span, 'top', 'height')
    assert sorted(p['name'] for p in bot_band) == ['CCaption', 'RemoteC', 'Tower2', 'pwsh']
    assert len(bot_band) == 4


def test_t_layout_bottom_includes_spanning_left_but_shared_split_is_same_cut():
    panes = [
        {'name': 'A', 'left': 0, 'width': 159, 'top': 0, 'height': 52},
        {'name': 'B', 'left': 160, 'width': 159, 'top': 0, 'height': 26},
        {'name': 'C', 'left': 160, 'width': 159, 'top': 27, 'height': 25},
    ]
    rows = cluster_groups(panes, 'top')
    top_span = min(p['height'] for p in rows[0]['panes'])
    bot_span = min(p['height'] for p in rows[1]['panes'])
    top_band = expand_band(panes, rows[0]['pos'], top_span, 'top', 'height')
    bot_band = expand_band(panes, rows[1]['pos'], bot_span, 'top', 'height')
    assert sorted(p['name'] for p in top_band) == ['A', 'B']
    assert sorted(p['name'] for p in bot_band) == ['A', 'C']
    assert {p['left'] for p in top_band if p['name'] != 'A'} == {160}
    assert {p['left'] for p in bot_band if p['name'] != 'A'} == {160}


def pane_in_direction(direction, current, candidate, slack=1):
    if direction == 'Left':
        if candidate['left'] >= current['left'] - slack:
            return None
        gap = current['left'] - candidate['left'] - candidate['width']
        dist = gap if gap >= 0 else current['left'] - candidate['left']
        return dist, ranges_overlap_exclusive(
            candidate['top'], candidate['height'], current['top'], current['height'])
    if direction == 'Right':
        if candidate['left'] <= current['left'] + slack:
            return None
        gap = candidate['left'] - current['left'] - current['width']
        dist = gap if gap >= 0 else candidate['left'] - current['left']
        return dist, ranges_overlap_exclusive(
            candidate['top'], candidate['height'], current['top'], current['height'])
    return None


def test_overlapping_moved_pane_is_reachable_to_the_right():
    # Prefix+Shift+N 後：左欄仍 319 寬，移入的 pane 疊在 left=160。
    current = {'left': 0, 'width': 319, 'top': 0, 'height': 26}
    moved = {'left': 160, 'width': 159, 'top': 0, 'height': 52}
    assert current['left'] + current['width'] > moved['left']
    hit = pane_in_direction('Right', current, moved)
    assert hit is not None
    assert hit[1]


def test_zero_width_right_panes_stay_in_right_column():
    left = {'name': 'A', 'left': 0, 'width': 120, 'top': 0, 'height': 40}
    right_top = {'name': 'B', 'left': 120, 'width': 0, 'top': 0, 'height': 20}
    right_bot = {'name': 'C', 'left': 120, 'width': 0, 'top': 20, 'height': 20}
    parts = partition_infos([left, right_top, right_bot], 120, 'left', 'width')
    assert parts is not None
    before, after = parts
    assert [p['name'] for p in before] == ['A']
    assert [p['name'] for p in after] == ['B', 'C']


if __name__ == '__main__':
    test_shrink_first_column_does_not_hit_window_edge()
    test_grow_first_column_still_moves_inner_edge()
    test_zero_width_right_panes_stay_in_right_column()
    test_stale_wide_mux_equalize_matches_window_not_mux_sum()
    test_stale_narrow_left_grows_to_half_window()
    test_grid_misaligned_is_two_rows_not_three_columns()
    test_window_usable_only_when_mux_disagrees()
    test_tab3_spanning_left_is_in_both_width_rows()
    test_t_layout_bottom_includes_spanning_left_but_shared_split_is_same_cut()
    test_overlapping_moved_pane_is_reachable_to_the_right()
    print('ok')
