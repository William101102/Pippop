export default async function run(page, ui) {
  await page.waitForTimeout(1000);
  const snap = await ui.snapshot();
  const signupBtn = snap.match(/@(e\d+) button "(第一次来\？创建账号|创建账号)"/)?.[1];
  if (signupBtn) {
    await ui.click(signupBtn);
    await page.waitForTimeout(500);
  }
  const snap2 = await ui.snapshot();
  const grab = (label) => {
    const m = snap2.match(new RegExp(`@(e\\d+) textbox "${label}"`));
    return m ? m[1] : null;
  };
  const disp = grab('你的昵称');
  const user = grab('your_id');
  const email = grab('you@example.com');
  const pass = grab('至少 6 位');
  if (!email || !pass) return { error: 'fields missing', snap2 };
  const uid = 'qa' + Math.floor(Math.random() * 1e6);
  if (disp) await ui.fill(disp, 'QA Bot');
  if (user) await ui.fill(user, uid);
  await ui.fill(email, `${uid}@gmail.com`);
  await ui.fill(pass, 'qatest123456');
  const snap3 = await ui.snapshot();
  const submit = snap3.match(/@(e\d+) button "注册"/)?.[1];
  await ui.click(submit);
  await page.waitForTimeout(5000);
  const state = await page.evaluate(() => {
    const mapEl = document.querySelector('.map');
    const leaflet = document.querySelector('.leaflet-container');
    const tiles = document.querySelectorAll('.leaflet-tile').length;
    const panes = document.querySelectorAll('.leaflet-pane').length;
    return {
      hasMapEl: !!mapEl,
      mapElSize: mapEl ? `${mapEl.offsetWidth}x${mapEl.offsetHeight}` : null,
      leafletInit: !!leaflet,
      panes,
      tilesLoaded: tiles,
      bodyText: document.body.innerText.slice(0, 300),
    };
  });
  await page.screenshot({ path: '.qa-after-signup.png', fullPage: false });
  return state;
}
