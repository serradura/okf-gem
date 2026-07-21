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
          .btn{cursor:pointer;display:inline-grid;place-items:center;width:34px;height:34px;border-radius:9px;border:1px solid var(--line);
           background:var(--panel);color:var(--muted);transition:color .15s,border-color .15s,background .15s;font-family:inherit}
          .btn:hover{color:var(--ink);border-color:var(--accent)}
          .btn:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
          .btn svg{width:16px;height:16px;stroke:currentColor;fill:none;stroke-width:1.7;stroke-linecap:round;stroke-linejoin:round}
          #btn-theme .sun{display:none} :root[data-theme=dark] #btn-theme .sun{display:block} :root[data-theme=dark] #btn-theme .moon{display:none}

          /* ── the message column ── */
          #views{flex:1;min-height:0;position:relative;background:var(--bg);overflow:auto;display:flex;flex-direction:column}
          #col{width:100%;max-width:620px;padding:44px 28px 24px;flex:1}
          /* the same 3px accent rule the graph page draws under a section head */
          h1{font-size:22px;font-weight:600;letter-spacing:-.015em;margin:0 0 18px;position:relative;padding-bottom:9px}
          h1::after{content:"";position:absolute;left:0;bottom:0;width:34px;height:3px;border-radius:3px;background:var(--accent)}
          .fact{margin:0 0 6px;color:var(--ink-soft)}
          .slug-chip{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12.5px;background:var(--line-2);
           border:1px solid var(--line);border-radius:6px;padding:2px 7px;color:var(--ink)}
          /* The one place this page raises its voice: the guess that saves the trip. */
          #didyoumean{margin:14px 0 0;font-size:14px;color:var(--muted)}
          #didyoumean a{color:var(--accent-ink);text-decoration:none;font-weight:600}
          #didyoumean a:hover{text-decoration:underline}
          .lbl{margin:26px 0 8px;font-size:10.5px;font-weight:600;text-transform:uppercase;letter-spacing:.06em;color:var(--faint)}

          /* ── the list: the palette's row anatomy, so a bundle looks the same here
                as it does under ⌘K on the graph page ── */
          #blist{list-style:none;margin:0;padding:0}
          #blist li[hidden]{display:none}
          #blist a{display:flex;align-items:center;gap:9px;padding:8px 10px;border-radius:8px;text-decoration:none;color:var(--ink);font-size:13.5px}
          #blist a:hover,#blist a.active{background:var(--line-2)}
          #blist a:focus-visible{outline:2px solid var(--accent);outline-offset:-2px}
          #blist .b-title{font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
          #blist .slug{color:var(--faint);font-size:12px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
          #blist .dbadge{padding:1px 7px;border-radius:99px;background:var(--line-2);color:var(--muted);font-size:11px}
          #blist .b-meta{margin-left:auto;display:flex;align-items:center;gap:12px;flex:none}
          #blist .b-cnt{color:var(--faint);font-size:12px;font-variant-numeric:tabular-nums}
          /* health carries a word in every state — colour is the echo, never the message */
          #blist .b-health{display:inline-flex;align-items:center;gap:6px;font-size:12px;color:var(--muted)}
          #blist .b-health .dot{width:7px;height:7px;border-radius:50%;background:currentColor}
          #blist .b-health.ok{color:var(--ok)} #blist .b-health.warn{color:var(--warn)} #blist .b-health.error{color:var(--accent-ink)}
          #bnone{margin:10px 0 0;padding:0 10px;color:var(--muted);font-size:13px}
          #bnone[hidden]{display:none}
          #bnone code{background:var(--line-2);border-radius:5px;padding:1px 5px;
           font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px}
          /* under the list, not pinned to the viewport floor: the keys act on
             the list, and a hint stranded 600px below it reads as unrelated */
          .ghint{margin:0;padding:18px 10px 0;color:var(--faint);font-size:11.5px}

          /* ≤768px: the rail is a whole drawer on the graph page; a 404 has
             nothing to put in one, so it folds away and the mark moves into the bar. */
          @media (max-width:768px){
           #app{grid-template-columns:1fr}
           #rail{display:none}
           #main{grid-column:1}
           .bar-brand{display:block}
           .search{flex-basis:140px}
           #col{padding:30px 18px 20px}
           #blist a{flex-wrap:wrap;gap:6px 9px}
           #blist .b-meta{margin-left:0;width:100%}
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
           var list=document.getElementById('blist'), none=document.getElementById('bnone'),
               chip=document.getElementById('bar-count'), total=list.children.length, cursor=-1;

           function rows(){
            return Array.prototype.filter.call(list.children,function(li){return !li.hidden;});
           }
           /* Total while the box is empty, matched/total once it is filtering —
              the same grammar the graph page's own count chip uses. */
           function count(shown){
            chip.textContent = q.value.trim()==='' ? String(total) : shown+'/'+total;
           }
           function paint(){
            var vis=rows();
            if(cursor>=vis.length) cursor=vis.length-1;
            Array.prototype.forEach.call(list.querySelectorAll('a.active'),function(a){a.classList.remove('active');});
            if(cursor>=0&&vis[cursor]){
             var a=vis[cursor].firstChild;
             a.classList.add('active');
             if(a.scrollIntoView) a.scrollIntoView({block:'nearest'});
            }
           }
           function filter(){
            var needle=q.value.trim().toLowerCase();
            Array.prototype.forEach.call(list.children,function(li){
             li.hidden = needle!=='' && li.getAttribute('data-hay').indexOf(needle)===-1;
            });
            var vis=rows();
            none.hidden = vis.length>0;
            count(vis.length);
            cursor = (needle!==''&&vis.length>0) ? 0 : -1;
            paint();
           }
           q.addEventListener('input',filter);
           q.addEventListener('keydown',function(ev){
            var vis=rows();
            if(ev.key==='ArrowDown'){ev.preventDefault();if(vis.length){cursor=Math.min(cursor+1,vis.length-1);paint();}}
            else if(ev.key==='ArrowUp'){ev.preventDefault();if(vis.length){cursor=Math.max(cursor-1,0);paint();}}
            else if(ev.key==='Enter'){if(cursor>=0&&vis[cursor]) location.href=vis[cursor].firstChild.href;}
            else if(ev.key==='Escape'){q.value='';filter();}
           });
           q.focus();
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
          body = %(<h1>No bundle here</h1>) +
                 %(<p class="fact"><span class="slug-chip">#{escape(@path)}</span> does not match a hosted bundle.</p>) +
                 guess + listing
          shell(body)
        end

        private

        # The guess that saves the trip, or nothing at all. A suggestion nobody
        # can use is worse than none: it sends a reader to a second wrong page
        # and spends the trust the first one already dented.
        def guess
          best = OKF.blank?(@slug) ? nil : nearest(@slug.to_s)
          return "" unless best

          %(<p id="didyoumean">Did you mean ) +
            %(<a href="#{link(best[:slug])}">@#{escape(best[:slug])}</a>) +
            %( — #{escape(best[:title])}?</p>)
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

          %(<p class="lbl">Bundles on this server</p><ul id="blist">) +
            @rows.map { |row| row_html(row) }.join +
            %(</ul><p id="bnone" hidden>No bundle matches.</p>) +
            %(<p class="ghint">↑↓ move · ⏎ open · esc clear</p>)
        end

        def row_html(row)
          badge = row[:default] ? %(<span class="dbadge">default</span>) : ""
          hay = "#{row[:slug]} #{row[:title]} #{row[:dir]}".downcase
          %(<li data-hay="#{escape(hay)}">) +
            %(<a href="#{link(row[:slug])}">) +
            %(<span class="b-title">#{escape(row[:title])}</span>) +
            %(<span class="slug">@#{escape(row[:slug])}</span>#{badge}) +
            %(<span class="b-meta"><span class="b-cnt">#{escape(concepts(row[:count]))}</span>) +
            %(<span class="b-health #{escape(row[:health])}"><span class="dot"></span>#{escape(row[:word])}</span>) +
            %(</span></a></li>)
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
            %(autocomplete="off" spellcheck="false" aria-label="Find a bundle">) +
            %(<span class="s-cnt" id="bar-count">#{total}</span></label>)
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
