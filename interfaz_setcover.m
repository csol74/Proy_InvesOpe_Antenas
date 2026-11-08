function interfaz_setcover()
%INTERFAZ_SETCOVER  Interfaz grafica para ejecutar y comparar el metodo exacto
%   (intlinprog) y el Algoritmo Genetico en el problema SET COVER.
%   Uso:  >> interfaz_setcover
%   Requiere MATLAB R2020a o superior y Optimization Toolbox.

    % ---------- Estado compartido ----------
    A = [];  c = [];  resEx = [];  resGA = [];  detener = false;

    % ---------- Ventana ----------
    fig  = uifigure('Name','SET COVER: Exacto vs Algoritmo Genetico', ...
                    'Position',[40 40 1280 760]);
    main = uigridlayout(fig,[1 2]);
    main.ColumnWidth = {310,'1x'};  main.Padding = [8 8 8 8];

    % ---------- Panel izquierdo (parametros y botones) ----------
    pl = uipanel(main,'Title','Panel de control');
    gl = uigridlayout(pl,[20 2]);
    gl.RowHeight = repmat({24},1,20);  gl.ColumnWidth = {'1x',90};
    gl.Padding = [8 8 8 8];  gl.RowSpacing = 5;

    boton(1,'1) Cargar datos (CSV + XLSX)',@(~,~)cargarDatos());
    lblDatos = uilabel(gl,'Text','Datos: sin cargar','FontColor',[0.5 0 0]);
    lblDatos.Layout.Row = 2;  lblDatos.Layout.Column = [1 2];

    seccion(3,'Solver exacto (intlinprog)');
    edTMax = campo(4,'Tiempo maximo [s]',28800,[1 Inf]);

    seccion(5,'Algoritmo Genetico');
    edPop  = campo(6,'Poblacion',200,[10 5000]);
    edGen  = campo(7,'Generaciones max.',3000,[10 100000]);
    edPc   = campo(8,'Prob. cruce (pc)',0.9,[0 1]);
    edPm   = campo(9,'Prob. mutacion (pm)',0.005,[0 1]);
    edK    = campo(10,'Tamano torneo (k)',3,[2 20]);
    edEl   = campo(11,'Elitismo',3,[0 50]);
    edPac  = campo(12,'Paciencia (gens)',200,[5 100000]);
    edSem  = campo(13,'Semilla',1,[0 1e6]);
    edCorr = campo(14,'Corridas del AG',5,[1 100]);

    boton(16,'2) Resolver EXACTO',@(~,~)ejecutarExacto());
    boton(17,'3) Ejecutar AG',@(~,~)ejecutarGA());
    boton(18,'4) Ejecutar AMBOS y comparar',@(~,~)ejecutarAmbos());
    bStop = boton(19,'Detener AG',@(~,~)setDetener());
    bStop.BackgroundColor = [0.95 0.75 0.75];
    boton(20,'Exportar resultados',@(~,~)exportar());

    % ---------- Panel derecho (pestanas) ----------
    tg = uitabgroup(main);

    tRes = uitab(tg,'Title','Resumen');
    gr = uigridlayout(tRes,[2 1]);  gr.RowHeight = {'1x','1x'};
    tabla = uitable(gr);
    tabla.ColumnName = {'Metodo','Costo','Gap vs exacto [%]','Tiempo [s]','N. antenas','Observacion'};
    tabla.ColumnWidth = {170,80,120,90,90,'auto'};
    bitacora = uitextarea(gr,'Editable','off');
    bitacora.Value = {'Bienvenido. Cargue los datos para comenzar.'};

    tCnv = uitab(tg,'Title','Convergencia');
    gc = uigridlayout(tCnv,[1 1]);
    axConv = uiaxes(gc);  titulo(axConv,'Convergencia del AG','Generacion','Costo');

    tCmp = uitab(tg,'Title','Comparacion');
    gm = uigridlayout(tCmp,[1 2]);
    axCosto  = uiaxes(gm);  titulo(axCosto,'Calidad de la solucion','','Costo total');
    axTiempo = uiaxes(gm);  titulo(axTiempo,'Tiempo de computo','','Segundos');

    tSol = uitab(tg,'Title','Cobertura de la solucion');
    gs = uigridlayout(tSol,[1 2]);
    axCovEx = uiaxes(gs);  titulo(axCovEx,'Exacto: antenas por cliente','Cliente','# antenas');
    axCovGA = uiaxes(gs);  titulo(axCovGA,'AG: antenas por cliente','Cliente','# antenas');

    tDis = uitab(tg,'Title','Corridas del AG');
    gd = uigridlayout(tDis,[1 1]);
    axDist = uiaxes(gd);  titulo(axDist,'Distribucion del costo final del AG','Costo','Frecuencia');

    % =================== CALLBACKS ===================
    function cargarDatos()
        f1 = 'set_cover_500x500.csv';  f2 = 'Costo_S.xlsx';
        carp = fileparts(mfilename('fullpath'));
        if isfile(fullfile(carp,f1)), f1 = fullfile(carp,f1); end
        if isfile(fullfile(carp,f2)), f2 = fullfile(carp,f2); end
        if ~isfile(f1)
            [a,b] = uigetfile('*.csv','Seleccione la matriz de cobertura (CSV)');
            if isequal(a,0), return; end
            f1 = fullfile(b,a);
        end
        if ~isfile(f2)
            [a,b] = uigetfile('*.xlsx','Seleccione el archivo de costos (XLSX)');
            if isequal(a,0), return; end
            f2 = fullfile(b,a);
        end
        try
            [A,c,m,n] = cargar_datos(f1,f2);
        catch ME
            uialert(fig,ME.message,'Error al cargar datos');  return;
        end
        lblDatos.Text = sprintf('Datos: %d clientes x %d antenas',m,n);
        lblDatos.FontColor = [0 0.4 0];
        escribir(sprintf('Datos cargados: %d x %d, densidad %.2f%%.',m,n,100*mean(A(:))));
    end

    function ejecutarExacto()
        if ~datosOK(), return; end
        d = uiprogressdlg(fig,'Title','Solver exacto', ...
            'Message','Resolviendo con intlinprog...','Indeterminate','on');
        try
            resEx = resolver_exacto(A,c,struct('tiempoMax',edTMax.Value,'display','off','tolRel',1e-3));
        catch ME
            close(d);  uialert(fig,ME.message,'Error en el solver exacto');  return;
        end
        close(d);
        escribir(sprintf('EXACTO: costo = %.0f | antenas = %d | t = %.2f s | gap = %.2e | LP = %.2f', ...
            resEx.fval,resEx.nSel,resEx.tiempo,resEx.gapRel,resEx.zLP));
        actualizar();
    end

    function ejecutarGA()
        if ~datosOK(), return; end
        detener = false;
        R = edCorr.Value;  tmp = cell(1,R);
        for r = 1:R
            p = parametrosGUI();  p.semilla = edSem.Value + r - 1;
            p.detenerFcn = @() detener;
            p.onGen = @(g,fb,h) vivo(g,h,r);
            [x,f,info] = ga_setcover(A,c,p);
            tmp{r} = struct('x',x,'f',f,'info',info);
            escribir(sprintf('AG corrida %d/%d: costo = %.0f | antenas = %d | gens = %d | t = %.2f s (%s)', ...
                r,R,f,info.nSel,info.generaciones,info.tiempo,info.motivo));
            if detener, break; end
        end
        tmp = tmp(~cellfun(@isempty,tmp));
        resGA = [tmp{:}];
        actualizar();
    end

    function ejecutarAmbos()
        if ~datosOK(), return; end
        ejecutarExacto();
        ejecutarGA();
    end

    function setDetener()
        detener = true;
    end

    function exportar()
        if isempty(resEx) && isempty(resGA)
            uialert(fig,'No hay resultados para exportar.','Aviso');  return;
        end
        carpeta = uigetdir(pwd,'Seleccione la carpeta de destino');
        if isequal(carpeta,0), return; end
        save(fullfile(carpeta,'resultados_interfaz.mat'),'resEx','resGA');
        try
            writecell([tabla.ColumnName'; tabla.Data],fullfile(carpeta,'resumen_interfaz.xlsx'));
            exportgraphics(axConv,fullfile(carpeta,'if_convergencia.png'),'Resolution',300);
            exportgraphics(axCosto,fullfile(carpeta,'if_costo.png'),'Resolution',300);
            exportgraphics(axTiempo,fullfile(carpeta,'if_tiempo.png'),'Resolution',300);
            exportgraphics(axDist,fullfile(carpeta,'if_distribucion.png'),'Resolution',300);
        catch ME
            uialert(fig,ME.message,'Exportacion parcial');
        end
        escribir(['Resultados exportados en: ' carpeta]);
    end

    % =================== FUNCIONES AUXILIARES ===================
    function vivo(g,h,r)
        if mod(g,5) == 0 || g == 1
            plot(axConv,h,'b-','LineWidth',1.8);
            titulo(axConv,sprintf('AG en ejecucion - corrida %d',r),'Generacion','Mejor costo');
            drawnow limitrate;
        end
    end

    function p = parametrosGUI()
        p = struct('popSize',round(edPop.Value),'maxGen',round(edGen.Value), ...
                   'pc',edPc.Value,'pm',edPm.Value,'torneo',round(edK.Value), ...
                   'elite',round(edEl.Value),'paciencia',round(edPac.Value), ...
                   'tolMejora',1e-6,'ventana',500,'maxReinicios',3);
    end

    function actualizar()
        % ---- Tabla resumen ----
        filas = {};
        refCosto = NaN;
        if ~isempty(resEx) && ~isnan(resEx.fval), refCosto = resEx.fval; end
        if ~isempty(resEx)
            if resEx.optimo, obs = 'Optimo comprobado'; else, obs = 'Mejor solucion hallada (limite de tiempo)'; end
            filas(end+1,:) = {'Exacto (intlinprog)',resEx.fval,0,resEx.tiempo,resEx.nSel,obs}; %#ok<AGROW>
        end
        if ~isempty(resGA)
            fs = [resGA.f];  ts = arrayfun(@(s) s.info.tiempo,resGA);
            ns = arrayfun(@(s) s.info.nSel,resGA);
            [fb,ib] = min(fs);
            gp = @(v) 100*(v-refCosto)/refCosto;
            filas(end+1,:) = {'AG - mejor corrida',fb,gp(fb),ts(ib),ns(ib),''}; %#ok<AGROW>
            filas(end+1,:) = {'AG - promedio',mean(fs),gp(mean(fs)),mean(ts),mean(ns), ...
                              sprintf('Desv. = %.2f (%d corridas)',std(fs),numel(fs))}; %#ok<AGROW>
            filas(end+1,:) = {'AG - peor corrida',max(fs),gp(max(fs)),max(ts),max(ns),''}; %#ok<AGROW>
        end
        tabla.Data = filas;

        % ---- Convergencia (mejor corrida) ----
        cla(axConv);
        if ~isempty(resGA)
            h = resGA(ib).info;
            hold(axConv,'on');
            plot(axConv,h.mejorHist,'b-','LineWidth',2);
            plot(axConv,h.mediaHist,'Color',[0.85 0.4 0.1],'LineWidth',1.2);
            leyenda = {'Mejor del AG','Promedio poblacion'};
            if ~isnan(refCosto)
                yline(axConv,refCosto,'k--','LineWidth',1.5);  leyenda{end+1} = 'Optimo exacto';
            end
            if ~isempty(resEx) && ~isnan(resEx.zLP)
                yline(axConv,resEx.zLP,'g:','LineWidth',1.5);  leyenda{end+1} = 'Cota LP';
            end
            hold(axConv,'off');
            legend(axConv,leyenda,'Location','northeast');
            titulo(axConv,'Convergencia del AG (mejor corrida)','Generacion','Costo');
        end

        % ---- Comparacion ----
        cla(axCosto);  cla(axTiempo);
        etq = {};  vc = [];  vt = [];
        if ~isempty(resEx), etq{end+1} = 'Exacto'; vc(end+1) = resEx.fval; vt(end+1) = resEx.tiempo; end
        if ~isempty(resGA)
            etq{end+1} = 'AG mejor';  vc(end+1) = fb;        vt(end+1) = ts(ib);
            etq{end+1} = 'AG medio';  vc(end+1) = mean(fs);  vt(end+1) = mean(ts);
        end
        if ~isempty(vc)
            bar(axCosto,categorical(etq,etq),vc);   titulo(axCosto,'Calidad de la solucion','','Costo total');
            bar(axTiempo,categorical(etq,etq),vt);  titulo(axTiempo,'Tiempo de computo','','Segundos');
        end

        % ---- Cobertura ----
        cla(axCovEx);  cla(axCovGA);
        if ~isempty(resEx) && ~isempty(resEx.x)
            bar(axCovEx,A*double(resEx.x(:)));
            titulo(axCovEx,sprintf('Exacto: %d antenas',resEx.nSel),'Cliente','# antenas que lo cubren');
        end
        if ~isempty(resGA)
            bar(axCovGA,A*double(resGA(ib).x(:)));
            titulo(axCovGA,sprintf('AG: %d antenas',ns(ib)),'Cliente','# antenas que lo cubren');
        end

        % ---- Distribucion ----
        cla(axDist);
        if ~isempty(resGA)
            histogram(axDist,fs);
            hold(axDist,'on');
            if ~isnan(refCosto), xline(axDist,refCosto,'k--','LineWidth',2); end
            hold(axDist,'off');
            titulo(axDist,'Distribucion del costo final del AG','Costo','Frecuencia');
        end
    end

    function ok = datosOK()
        ok = ~isempty(A);
        if ~ok, uialert(fig,'Primero cargue los datos.','Aviso'); end
    end

    function escribir(msg)
        bitacora.Value = [bitacora.Value; {[datestr(now,'HH:MM:SS') '  ' msg]}];
        scroll(bitacora,'bottom');
        drawnow limitrate;
    end

    % ---------- Constructores de controles ----------
    function b = boton(fila,txt,cb)
        b = uibutton(gl,'Text',txt,'ButtonPushedFcn',cb);
        b.Layout.Row = fila;  b.Layout.Column = [1 2];
    end

    function ed = campo(fila,txt,val,lim)
        l = uilabel(gl,'Text',txt);  l.Layout.Row = fila;  l.Layout.Column = 1;
        ed = uieditfield(gl,'numeric','Value',val,'Limits',lim);
        ed.Layout.Row = fila;  ed.Layout.Column = 2;
    end

    function seccion(fila,txt)
        l = uilabel(gl,'Text',txt,'FontWeight','bold');
        l.Layout.Row = fila;  l.Layout.Column = [1 2];
    end
end

function titulo(ax,t,xl,yl)
    title(ax,t);  xlabel(ax,xl);  ylabel(ax,yl);  grid(ax,'on');
end
