require 'sketchup.rb'
require 'extensions.rb'

module MaterialAreaCalculatorPro

  PLUGIN_ID      = 'material_area_calculator_pro'.freeze
  PLUGIN_VERSION = '2.2.0'.freeze

  SQIN_TO_SQFT = 1.0 / 144.0
  SQIN_TO_SQM  = 0.00064516
  SQIN_TO_SQYD = 1.0 / 1296.0

  def self.area_scale(transform)
    sx = transform.xaxis.length
    sy = transform.yaxis.length
    sz = transform.zaxis.length
    avg = (sx * sy * sz) ** (1.0 / 3.0)
    avg ** 2
  end

  def self.collect_face_areas(entities, transform, parent_material, results, only_visible)
    entities.each do |entity|
      if only_visible
        next if entity.hidden?
        next if entity.respond_to?(:layer) && entity.layer && !entity.layer.visible?
      end

      case entity
      when Sketchup::Face
        area_sqin = entity.area * area_scale(transform)
        mat = entity.material || entity.back_material || parent_material
        next if mat.nil?
        results[mat.name] = (results[mat.name] || 0.0) + area_sqin

      when Sketchup::Group
        child_transform = transform * entity.transformation
        inherited_mat   = entity.material || parent_material
        collect_face_areas(entity.entities, child_transform, inherited_mat, results, only_visible)

      when Sketchup::ComponentInstance
        child_transform = transform * entity.transformation
        inherited_mat   = entity.material || parent_material
        collect_face_areas(entity.definition.entities, child_transform, inherited_mat, results, only_visible)
      end
    end
  end

  def self.scan_model(only_visible: true)
    model    = Sketchup.active_model
    results  = {}
    identity = Geom::Transformation.new
    begin
      collect_face_areas(model.entities, identity, nil, results, only_visible)
    rescue => e
      UI.messagebox("Scan error: #{e.message}\n\nPartial results will be shown.")
    end
    results
  end

  def self.format_row(sq_in)
    {
      sqft: (sq_in * SQIN_TO_SQFT).round(2),
      sqm:  (sq_in * SQIN_TO_SQM ).round(4),
      sqyd: (sq_in * SQIN_TO_SQYD).round(3),
      sqin: sq_in.round(1)
    }
  end

  def self.build_json(results)
    rows = results
      .sort_by { |_, v| -v }
      .map do |name, sq_in|
        r = format_row(sq_in)
        safe_name = name.gsub('\\', '\\\\').gsub('"', '\\"')
        "{\"name\":\"#{safe_name}\"," \
        "\"sqft\":#{r[:sqft]}," \
        "\"sqm\":#{r[:sqm]}," \
        "\"sqyd\":#{r[:sqyd]}," \
        "\"sqin\":#{r[:sqin]}}"
      end
    "[#{rows.join(',')}]"
  end

  def self.export_csv(results)
    path = UI.savepanel('Save material areas as CSV', Dir.home, 'material_areas.csv')
    return if path.nil?
    path += '.csv' unless path.end_with?('.csv')
    begin
      File.open(path, 'w') do |f|
        f.puts 'Material Name,Area (sq ft),Area (sq m),Area (sq yd),Area (sq in)'
        results.sort_by { |_, v| -v }.each do |name, sq_in|
          r = format_row(sq_in)
          f.puts "\"#{name.gsub('"', '""')}\",#{r[:sqft]},#{r[:sqm]},#{r[:sqyd]},#{r[:sqin]}"
        end
      end
      UI.messagebox("Exported successfully to:\n#{path}")
    rescue => e
      UI.messagebox("Export failed:\n#{e.message}")
    end
  end

  def self.dialog_html(json_data, only_visible)
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <style>
          *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: -apple-system, Arial, sans-serif; font-size: 13px; background: #f4f4f4; display: flex; flex-direction: column; height: 100vh; }
          header { background: #2c5282; color: #fff; padding: 10px 14px; flex-shrink: 0; }
          header h1 { font-size: 14px; font-weight: 600; }
          header p  { font-size: 11px; opacity: 0.7; margin-top: 2px; }
          .toolbar { display: flex; gap: 8px; padding: 8px 12px; background: #fff; border-bottom: 1px solid #ddd; align-items: center; flex-shrink: 0; }
          .toolbar input { flex: 1; padding: 5px 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 12px; }
          .toolbar select { padding: 5px 6px; border: 1px solid #ccc; border-radius: 4px; font-size: 12px; }
          .count { font-size: 11px; color: #777; white-space: nowrap; }
          .table-wrap { flex: 1; overflow-y: auto; }
          table { width: 100%; border-collapse: collapse; background: #fff; }
          thead { position: sticky; top: 0; z-index: 1; }
          th { background: #2c5282; color: #fff; padding: 7px 10px; text-align: left; cursor: pointer; font-size: 12px; user-select: none; }
          th:last-child { text-align: right; }
          th:hover { background: #2a4a7f; }
          td { padding: 6px 10px; border-bottom: 1px solid #ebebeb; font-size: 12px; }
          td:last-child { text-align: right; }
          tbody tr:hover td { background: #eef2ff; }
          .no-data { text-align: center; padding: 20px; color: #999; }
          footer { display: flex; gap: 8px; padding: 8px 12px; background: #fff; border-top: 1px solid #ddd; align-items: center; flex-shrink: 0; }
          button { padding: 6px 14px; border: none; border-radius: 4px; cursor: pointer; font-size: 12px; font-weight: 500; }
          .btn-primary { background: #2c5282; color: #fff; }
          .btn-primary:hover { background: #2a4a7f; }
          .btn-secondary { background: #e2e8f0; color: #333; }
          .btn-secondary:hover { background: #cbd5e0; }
          .total { margin-left: auto; font-weight: 600; font-size: 12px; color: #2c5282; }
        </style>
      </head>
      <body>
        <header>
          <h1>Material Area Calculator Pro</h1>
          <p>v#{PLUGIN_VERSION} &mdash; #{only_visible ? 'Visible geometry only' : 'All geometry including hidden'}</p>
        </header>
        <div class="toolbar">
          <input type="text" id="search" placeholder="Filter by material name..." oninput="applyFilter()">
          <select id="unit" onchange="renderTable()">
            <option value="sqft">sq ft</option>
            <option value="sqm">sq m</option>
            <option value="sqyd">sq yd</option>
            <option value="sqin">sq in</option>
          </select>
          <span class="count" id="count"></span>
        </div>
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th id="th-name" onclick="sortBy('name')">Material ▲</th>
                <th id="th-area" onclick="sortBy('area')">sq ft ▼</th>
              </tr>
            </thead>
            <tbody id="tbody"></tbody>
          </table>
        </div>
        <footer>
          <button class="btn-primary"   onclick="sketchup.export_csv()">Export CSV</button>
          <button class="btn-secondary" onclick="sketchup.rescan()">Rescan</button>
          <button class="btn-secondary" onclick="sketchup.about()">About</button>
          <span class="total" id="total"></span>
        </footer>
        <script>
          var ALL_DATA  = #{json_data};
          var filtered  = ALL_DATA.slice();
          var sortCol   = 'area';
          var sortAsc   = false;
          var UNIT_LABELS = { sqft: 'sq ft', sqm: 'sq m', sqyd: 'sq yd', sqin: 'sq in' };

          function renderTable() {
            var unit  = document.getElementById('unit').value;
            var label = UNIT_LABELS[unit];
            var thArea = document.getElementById('th-area');
            var arrow  = thArea.textContent.slice(-2);
            thArea.textContent = label + ' ' + arrow;

            if (filtered.length === 0) {
              document.getElementById('tbody').innerHTML = '<tr><td class="no-data" colspan="2">No materials found</td></tr>';
              document.getElementById('total').textContent = '';
              document.getElementById('count').textContent = '0 materials';
              return;
            }

            var html = '', sum = 0;
            filtered.forEach(function(r) {
              sum += r[unit];
              html += '<tr><td>' + esc(r.name) + '</td><td>' + r[unit] + '</td></tr>';
            });
            document.getElementById('tbody').innerHTML = html;
            document.getElementById('total').textContent = 'Total: ' + sum.toFixed(2) + ' ' + label;
            document.getElementById('count').textContent = filtered.length + ' / ' + ALL_DATA.length + ' material(s)';
          }

          function applyFilter() {
            var q = document.getElementById('search').value.toLowerCase();
            filtered = ALL_DATA.filter(function(r) { return r.name.toLowerCase().indexOf(q) !== -1; });
            sortData();
            renderTable();
          }

          function sortBy(col) {
            var thName = document.getElementById('th-name');
            var thArea = document.getElementById('th-area');
            if (sortCol === col) { sortAsc = !sortAsc; } 
            else { sortCol = col; sortAsc = col === 'name'; }
            var unit  = document.getElementById('unit').value;
            var label = UNIT_LABELS[unit];
            thName.textContent = 'Material ' + (sortCol === 'name' ? (sortAsc ? '▲' : '▼') : '');
            thArea.textContent = label + ' '  + (sortCol === 'area' ? (sortAsc ? '▲' : '▼') : '');
            sortData();
            renderTable();
          }

          function sortData() {
            var unit = document.getElementById('unit').value;
            filtered.sort(function(a, b) {
              if (sortCol === 'name') {
                return sortAsc ? a.name.localeCompare(b.name) : b.name.localeCompare(a.name);
              }
              return sortAsc ? a[unit] - b[unit] : b[unit] - a[unit];
            });
          }

          function esc(s) { return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
          sortData();
          renderTable();
        </script>
      </body>
      </html>
    HTML
  end

  def self.show_dialog(only_visible: true)
    results = scan_model(only_visible: only_visible)

    if results.empty?
      UI.messagebox("No painted materials found.\n\nMake sure faces in your model have materials assigned.\nTry 'Calculate (all geometry)' if geometry is on hidden layers.")
      return
    end

    json = build_json(results)

    dlg = UI::HtmlDialog.new(
      dialog_title:    'Material Area Calculator Pro',
      preferences_key: PLUGIN_ID,
      width:           520,
      height:          560,
      resizable:       true
    )

    dlg.set_html(dialog_html(json, only_visible))
    dlg.add_action_callback('export_csv') { |_ctx| export_csv(results) }
    
    dlg.add_action_callback('rescan') do |_ctx|
      dlg.close
      UI.start_timer(0.1, false) { show_dialog(only_visible: only_visible) }
    end

    dlg.add_action_callback('about') do |_ctx|
      UI.messagebox("Material Area Calculator Pro\nVersion #{PLUGIN_VERSION}\n\nCalculates total face area per material.\nSupports recursive groups, components,\nmaterial inheritance, and visibility filtering.")
    end

    dlg.show
    dlg.bring_to_front
  end

  unless file_loaded?(__FILE__)
    sub = UI.menu('Extensions').add_submenu('Material Area Calculator Pro')
    sub.add_item('Calculate (visible geometry only)') { show_dialog(only_visible: true)  }
    sub.add_item('Calculate (all geometry)')          { show_dialog(only_visible: false) }
    sub.add_separator
    sub.add_item('About') do
      UI.messagebox("Material Area Calculator Pro\nVersion #{PLUGIN_VERSION}\n\nCalculates total face area per material.\nSupports recursive groups, components,\nmaterial inheritance, and visibility filtering.")
    end
    file_loaded(__FILE__)
  end

end