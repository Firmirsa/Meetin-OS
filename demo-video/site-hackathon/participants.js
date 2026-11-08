// Renders the team roster from window.HACKATHON_TEAMS (participants-data.js)
// and lets the jury pick and announce the winning team.
(function () {
  const data = window.HACKATHON_TEAMS || { teams: [] };
  const teams = data.teams || [];
  const $ = (id) => document.getElementById(id);
  const list = $('teams');
  const empty = $('roster-empty');
  const search = $('roster-search');
  const bar = $('pick-bar');
  const dialog = $('winner');

  const slug = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
    .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  const initials = (name) => name.trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join('').toUpperCase();
  const teamMark = (name) => {
    const words = name.split(/[^A-Za-z0-9À-ÿ]+/).filter(Boolean);
    return (words.length > 1 ? words[0][0] + words[1][0] : words[0].slice(0, 2)).toUpperCase();
  };
  const el = (tag, cls, text) => {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text != null) node.textContent = text;
    return node;
  };
  const membersOf = (team) => (team.members || []).map((m) => (typeof m === 'string' ? { name: m } : m));
  const face = (m) => {
    if (m.photo) {
      const img = el('img', 'av');
      img.src = m.photo;
      img.alt = m.name;
      return img;
    }
    const av = el('span', 'av', initials(m.name));
    av.title = m.name;
    return av;
  };

  const people = teams.reduce((n, t) => n + membersOf(t).length, 0);
  $('roster-count').textContent = `${teams.length} teams · ${people} builders`;

  // ── Roster ──────────────────────────────────────────────────────
  teams.forEach((team, i) => {
    const members = membersOf(team);
    const li = el('li', 'row' + (team.featured ? ' is-featured' : ''));
    li.id = 'team-' + (team.id || slug(team.name));
    li.dataset.search = [team.name, team.project, ...members.map((m) => m.name)].join(' ').toLowerCase();

    const pick = el('button', 'row-link');
    pick.type = 'button';
    pick.dataset.team = team.name;
    pick.dataset.index = String(i);
    pick.setAttribute('aria-pressed', 'false');

    const rank = el('span', 'row-rank', String(i + 1).padStart(2, '0'));
    const mark = el('span', 'row-mark', teamMark(team.name));
    mark.dataset.tone = String(i % 4);

    const main = el('span', 'row-main');
    const name = el('span', 'row-name', team.name);
    name.append(el('span', 'row-badge', 'Winner'));
    main.append(name);
    if (team.project) main.append(el('span', 'row-project', team.project));

    const avatars = el('span', 'row-avatars');
    members.forEach((m) => avatars.append(face(m)));
    avatars.append(el('span', 'row-size', String(members.length)));

    pick.append(rank, mark, main, avatars);
    li.append(pick);
    list.append(li);
  });

  // ── Search ──────────────────────────────────────────────────────
  const filter = () => {
    const q = search.value.trim().toLowerCase();
    let shown = 0;
    list.querySelectorAll('.row').forEach((row) => {
      const match = !q || row.dataset.search.includes(q);
      row.hidden = !match;
      if (match) shown++;
    });
    empty.hidden = shown > 0;
  };
  search.addEventListener('input', filter);
  filter();

  // ── Pick the winner ─────────────────────────────────────────────
  let selected = null;
  const select = (button) => {
    list.querySelectorAll('.row-link[aria-pressed="true"]').forEach((b) => b.setAttribute('aria-pressed', 'false'));
    selected = button === selected ? null : button;
    if (selected) selected.setAttribute('aria-pressed', 'true');
    bar.hidden = !selected;
    if (selected) $('pick-bar-team').textContent = selected.dataset.team;
  };
  list.addEventListener('click', (e) => {
    const button = e.target.closest('.row-link');
    if (button) select(button);
  });
  $('pick-cancel').addEventListener('click', () => select(selected));

  // ── Winner celebration ──────────────────────────────────────────
  const confetti = new window.Confetti($('confetti'));
  let timers = [];
  const later = (ms, fn) => timers.push(setTimeout(fn, ms));
  const clearTimers = () => { timers.forEach((t) => { clearTimeout(t); clearInterval(t); }); timers = []; };

  const cannons = (count, speed) => {
    const w = window.innerWidth;
    const h = window.innerHeight;
    confetti.cannon(0, h, -58, 34, count, speed);
    confetti.cannon(w, h, -122, 34, count, speed);
  };

  const celebrate = (team) => {
    const word = $('winner-word');
    word.replaceChildren(...'WINNER'.split('').map((letter, i) => {
      const outer = el('span', 'w-l');
      outer.style.setProperty('--i', i);
      outer.style.setProperty('--r', ((i % 2 ? 1 : -1) * (20 + i * 9)) + 'deg');
      outer.append(el('span', null, letter));
      return outer;
    }));

    $('winner-name').textContent = team.name;
    $('winner-faces').replaceChildren(...membersOf(team).map((m, i) => {
      const fig = el('figure', 'w-face');
      fig.style.setProperty('--i', i);
      fig.append(face(m), el('figcaption', null, m.name));
      return fig;
    }));

    const chunk = `Winner ★ ${team.name} ★ 1st place ★ Computer Use Agents Hackathon ★ `;
    ['band-top', 'band-bottom'].forEach((id) => { $(id).textContent = chunk.repeat(8); });

    clearTimers();
    confetti.stop();
    dialog.showModal();

    later(80, () => cannons(220, 34));
    later(250, () => confetti.rain(7000));
    later(1000, () => {
      const r = $('winner-team').getBoundingClientRect();
      confetti.burst(r.left + r.width / 2, r.top + r.height / 2, 180, 24);
    });
    later(2300, () => cannons(160, 30));
    later(3800, () => {
      cannons(120, 28);
      timers.push(setInterval(() => cannons(90, 26), 3200));
    });
  };

  $('pick-confirm').addEventListener('click', () => {
    if (!selected) return;
    const team = teams[Number(selected.dataset.index)];
    list.querySelectorAll('.row.is-winner').forEach((r) => r.classList.remove('is-winner'));
    selected.parentElement.classList.add('is-winner');
    select(selected);
    celebrate(team);
  });

  $('winner-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('close', () => {
    if (dialog.open) return;
    clearTimers();
    confetti.stop();
  });
})();
