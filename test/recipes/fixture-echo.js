// purpose: fixture recipe: fill the name box, click Save, return what the page shows
// args: port (fixture server port), name (optional, default "recipe")
// returns: {title, name, log}
// verified: 2026-11-26
// url: http://127.0.0.1:{port}/fixture.html?v={name|recipe}
await umb.wait(() => document.querySelector('#plain'), 5000);
umb.fill('css:"#name"', args.name ?? 'recipe');
await umb.click('text:"Plain span"');
const log = umb.text('#log', 100);
if (log !== 'span clicked') throw Error(`step failed: click: log says "${log}"`);
return { title: document.title, name: umb.find('css:"#name"').value, log };
