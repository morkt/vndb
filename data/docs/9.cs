:TITLE:Diskusní boardy
:INC:index


:SUB:Představení
<p>
 VNDB obsahuje pěkně integrované diskusní boardy, které se dají používat k, no,
 diskusím. Protože nepoužíváme žádný populární nebo veřejně dostupný software
 na fóra, ale místo toho jsme něco napsali sami, tyto diskusní boardy mají několik
 odlišností oproti populárním boardům, na které můžete být zvyklí.
</p>


:SUB:Boardy
<p>
 Aby se zabezpečilo, že hledající lidé najdou váš příspěvek, všechny thready patří
 k jednomu nebo více 'boardům', které určují, o čem je daná diskuse. Podobá se to
 boardům na ostatních fórche, ale zde má každá položka v databázi svůj vlastní board
 a je možné odkázat thread do více než jednoho boardu. Použít se dají následující
 boardy:
</p>
<dl>
 <dt>db</dt><dd>
  Diskuse o VNDB. Toto je obecný board pro thready, které nejsou o žádné určité položce
  v databázi.
 </dd><dt>v#</dt><dd>
  Pro diskuse o určité vizuální novele. Board <i>v17</i>, například, se používá
  pro všechny thready ohledně vizuální novely <a href="/v17">v17</a>.
 </dd><dt>p#</dt><dd>
  Stejně jako <i>v#</i>, ale pro producenty.
 </dd><dt>u#</dt><dd>
  <i>u#</i> board se dá použít pro upozornění některého uživatele této stránky ohledně
  něčeho co by on/a měl/a vidět nebo k diskusi ohledně jeho/jejích editací. Podobá se to
  klasické funkci 'soukromých zpráv' na mnoha stránkách, až na to, že to není 'soukromé'...
 </dd><dt>an</dt><dd>
  Požíváno pro oznámení ohledně stránek. Pouze pro moderátory.
 </dd>
</dl>


:SUB:Formátování
<p>
 Pro formátování vašich příspěvků můžete použít následující kódy:
</p>
<dl>
 <dt>X# or X#.#</dt><dd>
  'VNDBID', jak jim říkáme. Jsou to písmena (d, p, r, u or v), za kterými následuje číslo a můžou být následovány
  tečkou a druhým číslem. VNDBID budou automaticky převedeny na odkazy na příslušnou stránku v databázi.
  Například pokud napíšete 'v4.4', pak dostanete '<a href="/v4.4">v4.4</a>'.
 </dd><dt>URL</dt><dd>
  Jakákoliv URL (bez použití [url] tagu, viz níže) bude převedena na odkaz, podobně jako VNDBID.
  Příklad: 'http://vndb.org/' bude naformátováno jako '<a href="http://vndb.org/">link</a>'.
 </dd><dt>[url]</dt><dd>
  Klasický BBCode [url] tag. Dá se použít poze v podobě <i>[url=link]název odkazu[/url]</i>.<br />
  Např. '[url=/v]Seznam vizuálních novel[/url] a [url=http://blicky.net/]nějaká externí stránka[/url]'
  bude zobrazeno jako '<a href="/v">Seznam vizuálních novel</a> a <a href="http://blicky.net/">nějaká externí stránka</a>'
 </dd><dt>[spoiler]</dt><dd>
  Tag [spoiler] by měl být použit pro skrytí informací, které by mohly pokazit potěšení z hraní vizuální novely
  lidem, kteří ji ještě nehráli.
 </dd><dt>[quote]</dt><dd>
  Pokud se odkazujete na jiné lidi, umístěte citovaný příspěvek do [quote] .. [/quote] bloku. Prosíme, povšimněte si,
  že populární syntaxe [quote=source] na VNDB nefunguje. (yet)
 </dd><dt>[raw]</dt><dd>
  Předveďte své dovednosti ve formátovacím kódu umístěním čehokoliv, co nechcete aby bylo naformátováno do [raw]
  tagu. Jakýkoliv formátovací kód do teď zmíněný bude v [raw] .. [/raw] bloku ignorován.
 </dd><dt>[code]</dt><dd>
  Podobá se tagu [raw], až na to, že text v [code] .. [/code] bloku je formátován
  do fontu s pevnou šířkou a ohraničen pěkným rámečkem pro oddělení od zbytku
  vašeho příspěvku.
 </dd>
</dl>
<p>
 Nemáme žádný tag [img] a pravděpodobně zde nikdy žádný nebude. Pokud chcete přidat
 do příspěvku screenshoty nebo jiné obrázky, pak je, prosíme, nahrajte na externí
 hostingovou službu (např. <a href="http://tinypic.com/" rel="nofollow">TinyPic</a>) a odkažte na ně ve svém příspěvku.
</p>


