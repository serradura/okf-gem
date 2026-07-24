# frozen_string_literal: true

module OKF
  module Server
    class Hub
      # The page a stale bookmark lands on — and the only page in the product a
      # reader reaches by being wrong. So it is deliberately *not* a design of
      # its own: it is the app shell with nothing to show. The same 76px rail
      # with the ruby mark and the theme toggle, the same topbar, the same
      # `.search` component in the same position, the same row anatomy the
      # palette uses for a bundle, the same red-underlined head. Only the main
      # column differs. A 404 that looks like a different app tells a reader
      # they left the product, which is the opposite of the truth.
      #
      # Everything a reader needs is rendered here, in Ruby: the asked path, the
      # guess, the list. This is where someone lands when something has already
      # gone wrong, and a page that needs JavaScript to say what happened has
      # picked the worst moment to need it. The script adds the live filter, the
      # count, and ↑↓/⏎/esc — enhancements, every one of which the page is
      # complete without.
      #
      # The tokens, rail and topbar rules are copied from the graph template.
      # They are copied rather than shared because there is one other page that
      # wants them and an abstraction for two callers is a worse answer than two
      # copies; keep them in step if that template moves.
      class NotFound
        STYLE = <<~CSS
          :root{
           --bg:#ffffff; --panel:#ffffff; --canvas:#f4f5f7; --ink:#1f2328; --ink-soft:#333333;
           --muted:#63697a; --faint:#9298a4; --line:#e6e8eb; --line-2:#eef0f2;
           --accent:#e21e1e; --accent-ink:#c81a1a; --accent-soft:#fdecec; --ok:#1a9e5f; --warn:#9a6700;
           --rail:#15171c; --rail-ink:#8b919c; --rail-ink-hi:#dfe2e7;
          }
          :root[data-theme=dark]{
           --bg:#17191e; --panel:#1d2026; --canvas:#111318; --ink:#eceef1; --ink-soft:#d7dae0;
           --muted:#9aa0aa; --faint:#6b7178; --line:#2a2e36; --line-2:#232830;
           --accent:#f5433b; --accent-ink:#ff726b; --accent-soft:#3a1f1e; --ok:#37c07f; --warn:#d4a72c;
           --rail:#0d0e11; --rail-ink:#868c98; --rail-ink-hi:#e2e5ea;
          }
          *{box-sizing:border-box}
          html,body{margin:0;height:100%}
          body{background:var(--bg);color:var(--ink);
           font:14px/1.55 'Poppins',system-ui,-apple-system,Segoe UI,Roboto,sans-serif;-webkit-font-smoothing:antialiased}

          /* ── app shell: rail + main ── */
          #app{display:grid;grid-template-columns:76px 1fr;height:100vh;height:100dvh}
          #rail{grid-column:1;background:var(--rail);display:flex;flex-direction:column;align-items:center;gap:3px;padding:12px 8px;overflow:hidden}
          .rail-brand{width:34px;height:34px;margin:2px 0 10px;flex:none;display:block;border-radius:9px}
          .rail-brand svg{width:34px;height:34px;display:block}
          .rail-brand:focus-visible{outline:2px solid var(--accent);outline-offset:3px}
          .rail-sp{flex:1}
          .rail-tools{display:flex;flex-direction:column;gap:6px;align-items:center}
          .rail-tools .btn{color:var(--rail-ink);border-color:transparent;background:rgba(255,255,255,.05)}
          .rail-tools .btn:hover{color:var(--rail-ink-hi);background:rgba(255,255,255,.1);border-color:transparent}

          /* ── main column ── */
          #main{grid-column:2;display:flex;flex-direction:column;min-width:0}
          #topbar{flex:none;display:flex;align-items:center;gap:12px;padding:10px 16px;border-bottom:1px solid var(--line);background:var(--panel)}
          .bar-brand{display:none;width:26px;height:26px;flex:none}
          .bar-brand svg{width:26px;height:26px;display:block}

          /* ── shared controls (verbatim from the template) ── */
          .field{height:34px;border:1px solid var(--line);border-radius:9px;background:var(--panel);color:var(--ink);
           font:inherit;font-size:13px;padding:0 10px;outline:none;transition:border-color .15s,box-shadow .15s}
          .field:focus{border-color:var(--accent);box-shadow:0 0 0 3px var(--accent-soft)}
          .field::placeholder{color:var(--muted)}
          /* Sits where the graph page's box sits — right after the mark, not flush
             to the far edge: same component, same place, found by habit. */
          .search{position:relative;display:flex;align-items:center;flex:1 1 320px;min-width:130px;max-width:520px}
          .search svg{position:absolute;left:11px;width:15px;height:15px;stroke:var(--muted);fill:none;stroke-width:1.8;pointer-events:none}
          .search input{width:100%;padding-left:33px;padding-right:52px}
          /* The count sits on the control that filters, not in a heading that
             repeats it — the number belongs to what you are filtering. */
          .s-cnt{position:absolute;right:10px;top:50%;transform:translateY(-50%);font-size:11px;color:var(--faint);
           font-variant-numeric:tabular-nums;white-space:nowrap;pointer-events:none}
          /* ── the bridge, verbatim from the graph page ──
             The dead end is the same event here as there — the box in the topbar
             came up empty and there is somewhere else to look — so it is the same
             component in the same place, under the box that disappointed you,
             rather than a second dialect of the same idea two pages apart. ── */
          .s-bridge{position:absolute;top:calc(100% + 6px);left:0;right:0;z-index:60;background:var(--panel);
           border:1px solid var(--line);border-radius:11px;box-shadow:0 10px 30px rgba(0,0,0,.16);
           padding:11px 13px;font-size:12.5px}
          .s-bridge[hidden]{display:none}
          .sb-msg{color:var(--muted);margin-bottom:9px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
          .sb-msg b{color:var(--ink);font-weight:600}
          .sb-row{display:flex;gap:8px;flex-wrap:wrap}
          .sb-act{cursor:pointer;display:inline-flex;align-items:center;gap:7px;font-family:inherit;font-size:12px;
           padding:5px 10px;border:1px solid var(--line);border-radius:8px;background:var(--line-2);color:var(--muted);
           transition:color .15s,border-color .15s}
          .sb-act:hover{color:var(--ink);border-color:var(--accent)}
          .sb-act:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
          .sb-act.primary{color:var(--accent-ink);border-color:var(--accent);background:var(--accent-soft)}
          .sb-act kbd{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:10px;color:var(--faint);
           border:1px solid var(--line);border-radius:4px;padding:1px 4px;background:var(--panel);line-height:1.3}
          .btn{cursor:pointer;display:inline-grid;place-items:center;width:34px;height:34px;border-radius:9px;border:1px solid var(--line);
           background:var(--panel);color:var(--muted);transition:color .15s,border-color .15s,background .15s;font-family:inherit}
          .btn:hover{color:var(--ink);border-color:var(--accent)}
          .btn:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
          .btn svg{width:16px;height:16px;stroke:currentColor;fill:none;stroke-width:1.7;stroke-linecap:round;stroke-linejoin:round}
          #btn-theme .sun{display:none} :root[data-theme=dark] #btn-theme .sun{display:block} :root[data-theme=dark] #btn-theme .moon{display:none}

          /* ── the column ──
             Left-anchored under the rail and the bar, never centred: a card
             floating in the middle would read as a different page's chrome, and
             the two things this page shares with every other view are anchored
             hard left. 880px because the rows below carry a right-aligned fact
             column, and at 620 those columns had nowhere to be. ── */
          #views{flex:1;min-height:0;position:relative;background:var(--bg);overflow:auto;display:flex;flex-direction:column}
          #col{width:100%;max-width:880px;padding:40px 28px 28px;flex:1}

          /* ── what was asked for ──
             The heading and the path swap the usual sizes. A reader arrives here
             already knowing they are lost — the URL bar said so — so "not found"
             is the small word and the path they typed is the large one. Setting
             it in mono at 27px is what makes a dropped slash or a truncated slug
             legible as a *shape*, which is the one thing this page can do that
             the address bar cannot. ── */
          .eyebrow{margin:0 0 6px;font-size:11px;font-weight:600;text-transform:uppercase;
           letter-spacing:.08em;color:var(--faint)}
          h1{font-size:27px;font-weight:600;letter-spacing:-.02em;margin:0;padding-bottom:12px;position:relative;
           font-family:ui-monospace,SFMono-Regular,Menlo,monospace;color:var(--ink);
           overflow-wrap:anywhere;line-height:1.25}
          h1::after{content:"";position:absolute;left:0;bottom:0;width:34px;height:3px;border-radius:3px;background:var(--accent)}
          .fact{margin:14px 0 0;color:var(--muted);font-size:13.5px}
          .fact code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12.5px;color:var(--ink-soft)}

          /* ── the near miss ──
             The one place this page raises its voice, and it earns it by being
             the whole answer when it is right. A sentence in muted grey asks the
             reader to read, parse and then aim; a row asks them to press Enter.
             So the guess wears the same anatomy as the list below it, one step
             brighter, and the keyboard already points at it. ── */
          .miss{margin:24px 0 0}
          .miss[hidden]{display:none}
          .miss .lbl{margin:0 0 6px}

          .lbl{margin:30px 0 8px;font-size:10.5px;font-weight:600;text-transform:uppercase;
           letter-spacing:.06em;color:var(--faint)}

          /* ── the rows: the /b/ list's anatomy, which carries the folder ──
             The folder is not decoration here. A server hosting `site/.okf`,
             `minifts/.okf` and `okf-core/.okf` has three bundles whose titles are
             nearly the same word, and the directory they came from is the only
             thing that tells them apart. The old row omitted exactly that. ── */
          #blist{list-style:none;margin:0;padding:0}
          #blist li[hidden]{display:none}
          .brow{list-style:none}
          .brow a{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:1px 20px;align-items:center;
           padding:9px 13px;border-radius:10px;text-decoration:none;color:var(--ink);
           box-shadow:inset 3px 0 0 var(--edge,transparent);transition:background .12s}
          .brow a:hover{background:var(--line-2)}
          /* The cursor is one look wherever it stands — on the near miss, on a
             filtered bundle, on a concept hit — because ↑↓ walks all three as
             one list. The guess is not styled at all: it is simply where the
             cursor starts, which is why it is lit on arrival and stops being lit
             the moment you type. */
          /* The palette's own selection is this neutral fill, so the cursor
             matches it rather than inventing a louder one; the accent *edge* is
             what makes the move visible, and it is already this page's device
             for saying which row to look at. */
          .brow a.active{--edge:var(--accent);background:var(--line-2)}
          .brow a.active .dbadge{background:rgba(128,128,128,.22)}
          .brow a:focus-visible{outline:2px solid var(--accent);outline-offset:-2px}
          /* No edge at all on a healthy row. A rule per bundle is six marks
             saying "nothing to report", and a page where everything is marked
             is a page where the one thing that matters is not. */
          .brow[data-health=warn] a{--edge:var(--warn)}
          .brow[data-health=error] a{--edge:var(--accent)}
          .brow[data-health=missing] a{--edge:var(--faint)}
          .b-id{grid-column:1;grid-row:1;display:flex;align-items:baseline;gap:9px;min-width:0}
          .b-title{font-weight:500;font-size:14px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
          .slug{color:var(--faint);font-size:12px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;flex:none}
          .dbadge{padding:1px 7px;border-radius:99px;background:var(--line-2);color:var(--muted);font-size:10.5px;flex:none}
          /* Truncate a long path from the *left*: the tail (…/repo/.okf) is what
             identifies it, and clipping the tail identifies nothing. An rtl box
             puts the ellipsis at the front, and the inner <bdi> keeps the path
             itself one ltr run so a leading "/" cannot reorder to the far end. */
          .b-dir{grid-column:1;grid-row:2;font-size:11.5px;color:var(--faint);
           font-family:ui-monospace,SFMono-Regular,Menlo,monospace;
           overflow:hidden;text-overflow:ellipsis;white-space:nowrap;direction:rtl;text-align:left}
          .b-dir bdi{direction:ltr}
          /* fixed slots, right-aligned: read down the page as much as across,
             and a ragged column of numbers is a column nobody scans */
          .b-meta{grid-column:2;grid-row:1/3;display:flex;align-items:baseline;gap:20px;flex:none;
           font-size:12px;color:var(--faint)}
          .b-cnt{min-width:6.5rem;text-align:right;font-variant-numeric:tabular-nums}
          /* Colour marks the exception only. Six green "no problems" spends the
             page's whole palette on nothing to report — and makes the one real
             warning harder to find, which is the opposite of the job. */
          .b-health{min-width:7rem;color:var(--muted)}
          .brow[data-health=warn] .b-health{color:var(--warn)}
          .brow[data-health=error] .b-health{color:var(--accent-ink)}
          .brow[data-health=missing] .b-title{color:var(--faint);font-weight:400}
          #hits[hidden]{display:none}
          #hitlist{list-style:none;margin:0;padding:0}
          #hitnote{margin:10px 0 0;padding:0 13px;color:var(--faint);font-size:12px}
          /* a snippet is prose, so it drops the path row's mono and rtl clipping */
          .hit-s{font-family:inherit;direction:ltr;color:var(--muted);font-size:12.5px}
          #bnone code{background:var(--line-2);border-radius:5px;padding:1px 5px;
           font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px}

          /* ≤768px: the rail is a whole drawer on the graph page; a 404 has
             nothing to put in one, so it folds away and the mark moves into the bar. */
          @media (max-width:768px){
           #app{grid-template-columns:1fr}
           #rail{display:none}
           #main{grid-column:1}
           .bar-brand{display:block}
           .search{flex-basis:140px}
           #col{padding:28px 16px 20px}
           h1{font-size:20px}
           /* the fact columns stop being columns and become a third line */
           .brow a{grid-template-columns:minmax(0,1fr)}
           .b-meta{grid-column:1;grid-row:3;margin-top:3px;gap:14px}
           .b-cnt,.b-health{min-width:0}
          }
          @media (prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
        CSS

        # The ruby mark, the graph template's own. It appears twice — once in the
        # rail, once in the bar the rail folds into below 768px — because the two
        # are never visible at the same time.
        MARK = '<svg viewBox="0 0 100 100"><rect width="100" height="100" rx="24" fill="#1a1a1a"/>' \
               '<polygon points="38,44 62,44 50,82" fill="#7a0a1e"/><polygon points="18,44 38,44 50,82" fill="#a8112c"/>' \
               '<polygon points="62,44 82,44 50,82" fill="#a8112c"/><polygon points="35,28 18,44 38,44" fill="#dc1e3c"/>' \
               '<polygon points="65,28 82,44 62,44" fill="#dc1e3c"/><polygon points="35,28 65,28 62,44 38,44" fill="#f43f5e"/>' \
               '<polygon points="36,29 49,29 42,42" fill="#fff" opacity=".38"/>' \
               '<polygon points="35,28 65,28 82,44 50,82 18,44" fill="none" stroke="#ff6b7f" stroke-width="2" stroke-linejoin="round"/></svg>'

        # Filter, count and keyboard — the three things a static document cannot
        # do. Every row is already in the DOM; this only hides some of them.
        # Filter, count, keyboard, and the fallback to searching every bundle —
        # the four things a static document cannot do. Everything else on this
        # page is already in the DOM before this runs.
        SCRIPT = <<~JS
          (function(){
           'use strict';
           var root=document.documentElement;
           document.getElementById('btn-theme').addEventListener('click',function(){
            var next=root.getAttribute('data-theme')==='dark'?'light':'dark';
            root.setAttribute('data-theme',next);
            try{localStorage.setItem('okf-theme',next);}catch(e){}
           });

           var q=document.getElementById('q');
           if(!q) return;
           var list=document.getElementById('blist'),
               chip=document.getElementById('bar-count'), total=list.children.length,
               missBox=document.querySelector('.miss'),
               miss=missBox?missBox.querySelector('a'):null,
               hits=document.getElementById('hits'), hitList=document.getElementById('hitlist'),
               hitNote=document.getElementById('hitnote'), goBtn=document.getElementById('go-search'),
               bridge=document.getElementById('s-bridge'),
               bridgeMsg=bridge.querySelector('.sb-msg'),
               goBtn=document.getElementById('sb-go'), clearBtn=document.getElementById('sb-clear'),
               endpoint=q.getAttribute('data-search'), mount=q.getAttribute('data-mount'),
               searched=null;

           /* Moving through the list is Tab's job, and Tab already does it: every
              row is an <a href>, a filtered-out row is display:none and drops out
              of the order on its own, and Shift-Tab goes back. A hand-rolled ↑↓
              cursor was a second, worse focus model living beside the real one —
              it lit rows the browser did not consider focused, it was invisible
              to a screen reader, and keeping the two in step is what left two
              rows highlighted at once.
              What is left is not a cursor: one row is marked, it is whatever ⏎
              would open *right now*, and it never moves on its own. It stands
              down the moment the caret leaves the box, because past that point ⏎
              belongs to whatever Tab has focused. */
           function shownRows(){
            return Array.prototype.filter.call(list.children,function(li){return !li.hidden;});
           }
           function target(){
            if(miss&&q.value.trim()==='') return miss;
            var first=shownRows()[0];
            if(first) return first.firstChild;
            return hitList.children.length ? hitList.children[0].firstChild : null;
           }
           function unmark(){
            Array.prototype.forEach.call(document.querySelectorAll('a.active'),function(a){a.classList.remove('active');});
           }
           function mark(){
            unmark();
            var t=target();
            if(t) t.classList.add('active');
           }
           /* Total while the box is empty, matched/total once it is filtering —
              the same grammar the graph page's own count chip uses. */
           function count(shown){
            chip.textContent = q.value.trim()==='' ? String(total) : shown+'/'+total;
           }
           function filter(){
            var needle=q.value.trim().toLowerCase();
            Array.prototype.forEach.call(list.children,function(li){
             li.hidden = needle!=='' && li.getAttribute('data-hay').indexOf(needle)===-1;
            });
            /* The guess answers "what did you *ask* for", so a query supersedes
               it outright rather than sitting above the answer to a different
               question. */
            if(missBox) missBox.hidden = needle!=='';
            var vis=shownRows();
            /* The bridge is the graph page's own dead-end panel, doing the same
               job for the same reason: the box came up empty and there is
               somewhere else to look. It drops under the box rather than into
               the list, because that is where the reader is looking when the
               filter disappoints them. */
            var dead = needle!=='' && vis.length===0;
            bridge.hidden = !dead;
            if(dead){
             bridgeMsg.innerHTML='No bundle matches \u201c<b></b>\u201d';
             bridgeMsg.querySelector('b').textContent=q.value.trim();
            }
            /* A new query invalidates the last search — the hits below belong to
               a word nobody is looking at any more. */
            if(needle!==searched){hits.hidden=true;hitList.innerHTML='';hitNote.textContent='';searched=null;}
            count(vis.length);
            mark();
           }

           /* The dead end, and the way through it. A bundle list cannot answer
              "where is the thing about decay?" — but the hub can, because it
              searches inside every bundle it hosts. So a query that matches no
              *bundle* is offered the search that does match, rather than being
              told no twice. Same escalation the graph page's search box makes
              when its own bundle comes up empty. */
           function esc(s){return String(s==null?'':s).replace(/[&<>"']/g,function(c){
            return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];});}
           function hitRow(c){
            var href=mount+'/'+encodeURIComponent(c.slug)+'/?select='+encodeURIComponent(c.id);
            return '<li class="brow"><a href="'+esc(href)+'">'+
             '<span class="b-id"><span class="b-title">'+esc(c.title||c.id)+'</span>'+
             (c.type?'<span class="dbadge">'+esc(c.type)+'</span>':'')+
             '<span class="slug">@'+esc(c.slug)+'</span></span>'+
             (c.snippet?'<span class="b-dir hit-s">'+esc(c.snippet)+'</span>':'')+
             '</a></li>';
           }
           function search(){
            var term=q.value.trim();
            if(!term||!endpoint||searched===term.toLowerCase()) return;
            searched=term.toLowerCase();
            hits.hidden=false;hitList.innerHTML='';hitNote.textContent='searching every bundle…';
            var req=new XMLHttpRequest();
            req.open('GET',endpoint+'?q='+encodeURIComponent(term));
            req.onload=function(){
             if(q.value.trim().toLowerCase()!==searched) return;
             var data;
             try{data=JSON.parse(req.responseText);}catch(e){data=null;}
             var found=(data&&data.results)||[];
             hitList.innerHTML=found.map(hitRow).join('');
             hitNote.textContent = found.length ? (data.truncated?'showing '+found.length+' of '+data.total+' — narrow the search':'')
              : 'No concept matches either.';
             mark();
            };
            req.onerror=function(){hitNote.textContent='search is unavailable right now';};
            req.send();
           }
           goBtn.addEventListener('click',function(){search();q.focus();});
           clearBtn.addEventListener('click',function(){q.value='';filter();q.focus();});

           q.addEventListener('input',filter);
           /* The mark means "⏎ opens this", so it is only true while the caret is
              in the box. Tab away and ⏎ belongs to the focus ring instead. */
           q.addEventListener('blur',unmark);
           q.addEventListener('focus',mark);
           q.addEventListener('keydown',function(ev){
            if(ev.key==='Enter'){
             ev.preventDefault();
             var t=target();
             /* Nothing to open means the list is the wrong place to be looking,
                so ⏎ escalates rather than doing nothing. */
             if(t) location.href=t.href;
             else if(!bridge.hidden) search();
            }
            else if(ev.key==='Escape'){q.value='';filter();}
           });
           /* `/` reaches the box from anywhere on the page, the same key the graph
              page binds — a reader who tabbed into the list and changed their
              mind should not have to tab back out of it. */
           addEventListener('keydown',function(ev){
            if(ev.key!=='/'||ev.target===q||ev.metaKey||ev.ctrlKey||ev.altKey) return;
            if(ev.target.matches&&ev.target.matches('input,select,textarea')) return;
            ev.preventDefault();q.focus();q.select();
           });
           q.focus();
           mark();
          })();
        JS

        # +path+ is what was asked for, +slug+ the bundle name inside it (nil
        # when the path was not under the mount at all), +rows+ the hosted
        # bundles in the shape the manager already describes them, +base+ the
        # prefix a host mounted the hub under, +mount+ the /b prefix.
        def initialize(path, slug, rows, base, mount)
          @path = path
          @slug = slug
          @rows = rows
          @base = base
          @mount = mount
        end

        def self.page(*args)
          new(*args).page
        end

        def page
          shell(head + guess + listing)
        end

        private

        # The heading is the path, not the verdict. A reader arrives already
        # knowing they are lost, so "Not found" is the small word and what they
        # actually asked for is the large one — set in mono, where a dropped
        # slash or a truncated slug is legible as a shape rather than as prose.
        def head
          %(<p class="eyebrow">Not found</p>) +
            %(<h1>#{escape(@path)}</h1>) +
            fact
        end

        # One line, and only where it adds something the heading did not. When a
        # missing separator explains the whole trip, say that; otherwise teach
        # the shape, which is what someone who typed the path by hand needs.
        def fact
          if hosted?(segment)
            return %(<p class="fact">That bundle is served at ) +
                   %(<code>#{escape(@mount)}/#{escape(segment)}/</code> — the <code>#{escape(@mount)}/</code> is missing.</p>)
          end
          if dropped_slash
            return %(<p class="fact">That looks like <code>#{escape(@mount)}/#{escape(dropped_slash)}/</code> ) +
                   %(with the slash after <code>#{escape(@mount)}</code> dropped.</p>)
          end

          %(<p class="fact">Bundles are served at <code>#{escape(@mount)}/&lt;name&gt;/</code>.</p>)
        end

        # The guess that saves the trip, or nothing at all. A suggestion nobody
        # can use is worse than none: it sends a reader to a second wrong page
        # and spends the trust the first one already dented.
        #
        # It is a row rather than a sentence because a sentence asks a reader to
        # read it, parse it, and then go aiming; a row is already the thing they
        # were looking for, and ⏎ is already pointed at it.
        def guess
          best = nearest_row
          return "" unless best

          %(<div class="miss"><p class="lbl">Closest match</p>) +
            row_html(best, active: true) +
            %(</div>)
        end

        def nearest_row
          @guess = candidates.map { |c| nearest(c) }.compact.first unless defined?(@guess)
          @guess
        end

        # What to measure the hosted slugs against. Normally the slug the router
        # parsed out; when there was none, the path's own first segment — because
        # the commonest way a hand-typed URL fails is the separator, and
        # `/bnotes/` carries the answer in plain sight while the router, which
        # only ever looks under the mount, sees nothing at all.
        #
        # The whole segment is tried first, so a bundle genuinely named `borders`
        # beats `orders` reached by eating the mount letter.
        def candidates
          return [ @slug.to_s ] unless OKF.blank?(@slug)

          return [] if segment.empty?

          remainder.nil? ? [ segment ] : [ segment, remainder ]
        end

        def segment
          @segment ||= @path.to_s.sub(%r{\A/+}, "").sub(%r{/.*\z}m, "")
        end

        # The first path segment with the mount's own letters taken off the
        # front, or nil where that is not what the path looks like.
        def remainder
          bare = @mount.to_s.sub(%r{\A/+}, "")
          return nil if bare.empty? || !segment.start_with?(bare) || segment.length <= bare.length

          segment[bare.length..-1]
        end

        # A dropped separator is worth naming outright, but only on evidence that
        # leaves no room for a second reading: the remainder has to be a hosted
        # slug *exactly*, and the whole segment must not be one — a bundle really
        # called `borders` is reached by adding `/b/`, not by moving a slash.
        # Everything short of that gets the general sentence, which points at the
        # same fix without claiming to know what happened.
        def dropped_slash
          return nil if hosted?(segment)

          hosted?(remainder) ? remainder : nil
        end

        def hosted?(name)
          !OKF.blank?(name) && @rows.any? { |row| row[:slug].to_s == name }
        end

        # Edit distance, with a shortcut for a shared prefix. Truncation is the
        # commonest way a slug comes out wrong — a URL copied short, a tab
        # completion abandoned — and plain Levenshtein scores `ord` three edits
        # from `orders`, which is far. Treating a prefix as one edit is what
        # makes the guess land on the case that actually happens.
        #
        # The threshold scales with length so a short slug cannot match
        # everything (`a` is one edit from `b`) and a long one is not held to an
        # absolute that means nothing at its size.
        def nearest(asked)
          return nil if OKF.blank?(asked)

          lower = asked.downcase
          best = nil
          score = nil
          @rows.each do |row|
            candidate = row[:slug].to_s.downcase
            edits = distance(lower, candidate)
            edits = 1 if edits > 1 && (candidate.start_with?(lower) || lower.start_with?(candidate))
            next if score && edits >= score

            best = row
            score = edits
          end
          return nil unless best

          score <= threshold(lower, best[:slug].to_s) ? best : nil
        end

        def threshold(asked, candidate)
          [ 3, ([ asked.length, candidate.length ].max / 3.0).ceil ].min
        end

        # Levenshtein over one rolling row — the whole matrix is never needed,
        # only the previous line of it.
        def distance(from, to)
          row = (0..to.length).to_a
          from.length.times do |i|
            prev = row[0]
            row[0] = i + 1
            to.length.times do |j|
              carried = row[j + 1]
              cost = from[i] == to[j] ? 0 : 1
              row[j + 1] = [ row[j + 1] + 1, row[j] + 1, prev + cost ].min
              prev = carried
            end
          end
          row[to.length]
        end

        # A hub with nothing registered is a different failure from a slug that
        # matched nothing, and saying "no bundle matches" there would blame the
        # reader's query for the server's own empty list.
        def listing
          if @rows.empty?
            return %(<p class="lbl">Nothing to open</p>) +
                   %(<p id="bnone">No bundles are registered on this server. ) +
                   %(Register one with <code>okf registry set &lt;dir&gt;</code>, then restart <code>okf server</code>.</p>)
          end

          %(<p class="lbl">Bundles on this server</p><ul id="blist">#{@rows.map { |row| row_html(row) }.join}</ul>) +
            %(<div id="hits" hidden><p class="lbl">Concepts, across every bundle</p>) +
            %(<ul id="hitlist"></ul><p id="hitnote"></p></div>)
        end

        # One row, used twice: in the list, and as the near miss above it. The
        # guess being the *same object* as a list entry is the whole point —
        # whatever a reader learns to read here reads the same there.
        def row_html(row, active: false)
          badge = row[:default] ? %(<span class="dbadge">default</span>) : ""
          hay = "#{row[:slug]} #{row[:title]} #{row[:dir]}".downcase
          here = active ? %( class="active") : ""
          %(<li class="brow" data-health="#{escape(row[:health])}" data-hay="#{escape(hay)}">) +
            %(<a href="#{link(row[:slug])}"#{here}>) +
            %(<span class="b-id"><span class="b-title">#{escape(row[:title])}</span>) +
            %(<span class="slug">@#{escape(row[:slug])}</span>#{badge}</span>) +
            %(<span class="b-dir" title="#{escape(row[:dir])}"><bdi>#{escape(row[:dir])}</bdi></span>) +
            %(<span class="b-meta"><span class="b-cnt">#{escape(count_word(row[:count]))}</span>) +
            %(<span class="b-health">#{escape(row[:word])}</span></span>) +
            %(</a></li>)
        end

        def count_word(count)
          return "—" if count.nil?

          concepts(count)
        end

        def concepts(count)
          "#{count} #{count == 1 ? "concept" : "concepts"}"
        end

        # Absolute, prefix-carrying: this page is reached at paths of every
        # depth (/b/ghost/, /elsewhere), so a relative link would resolve
        # somewhere different depending on how the reader got here.
        def link(slug)
          "#{escape(@base)}#{@mount}/#{escape(slug)}/"
        end

        # An empty hub gets no search box: a control that filters nothing only
        # wastes the one action a reader has left. The count starts as the total
        # and the script swaps in n/total the moment it filters.
        def shell(body)
          search = @rows.empty? ? "" : search_box(@rows.length)
          home = %(href="#{escape(@base)}#{@mount}/" title="All bundles" aria-label="All bundles")
          <<~HTML
            <!doctype html><html lang="en"><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width,initial-scale=1">
            <meta name="color-scheme" content="dark light">
            <title>OKF · not found</title>
            <script>/* Resolve the theme before first paint, so there is no flash. */
            (function(){try{var t=localStorage.getItem('okf-theme')||(matchMedia('(prefers-color-scheme:dark)').matches?'dark':'light');document.documentElement.setAttribute('data-theme',t);}catch(e){}})();</script>
            <style>#{STYLE}</style>
            </head><body>
            <div id="app">
             <nav id="rail" aria-label="Bundles">
              <a class="rail-brand" #{home}>#{MARK}</a>
              <div class="rail-sp"></div>
              <div class="rail-tools">#{theme_button}</div>
             </nav>
             <div id="main">
              <header id="topbar">
               <a class="bar-brand" #{home}>#{MARK}</a>
               #{search}
              </header>
              <div id="views"><div id="col">#{body}</div></div>
             </div>
            </div>
            <script>#{SCRIPT}</script>
            </body></html>
          HTML
        end

        def search_box(total)
          %(<label class="search"><svg viewBox="0 0 24 24" fill="none"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>) +
            %(<input id="q" class="field" type="text" placeholder="find a bundle…" autofocus ) +
            %(autocomplete="off" spellcheck="false" aria-label="Find a bundle" ) +
            %(data-search="#{escape(@base)}/search" data-mount="#{escape(@base)}#{@mount}">) +
            %(<span class="s-cnt" id="bar-count">#{total}</span>) +
            %(<div id="s-bridge" class="s-bridge" role="status" hidden><div class="sb-msg"></div>) +
            %(<div class="sb-row">) +
            %(<button type="button" class="sb-act primary" id="sb-go">Search every bundle <kbd>⏎</kbd></button>) +
            %(<button type="button" class="sb-act" id="sb-clear">Clear <kbd>esc</kbd></button>) +
            %(</div></div></label>)
        end

        def theme_button
          %(<button class="btn" id="btn-theme" type="button" aria-label="Toggle theme">) +
            %(<svg class="moon" viewBox="0 0 24 24"><path d="M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5Z"/></svg>) +
            %(<svg class="sun" viewBox="0 0 24 24"><circle cx="12" cy="12" r="4.2"/>) +
            %(<path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.2 5.2l1.5 1.5M17.3 17.3l1.5 1.5M18.8 5.2l-1.5 1.5M6.7 17.3l-1.5 1.5"/></svg></button>)
        end

        def escape(str)
          Rack::Utils.escape_html(str.to_s)
        end
      end
    end
  end
end
