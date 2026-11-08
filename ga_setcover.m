function [xBest, fBest, info] = ga_setcover(A, c, p)
%GA_SETCOVER  Algoritmo Genetico MEMETICO para el SET COVER ponderado (v2).
%
%   Representacion : cromosoma binario x (1 x n); x_j = 1 si se instala la antena j.
%   Fitness        : f(x) = sum_j c_j x_j (se MINIMIZA) sobre soluciones SIEMPRE factibles.
%   Inicializacion : voraz aleatorizado tipo GRASP (Feo y Resende, 1995) con la regla
%                    costo / cobertura nueva de Chvatal (1979); individuos distintos y de calidad.
%   Seleccion      : torneo de tamano k.
%   Cruce          : 'fusion'  -> cruce basado en aptitud de Beasley y Chu (1996)
%                    'union'   -> union de padres + minimalizacion (Tayebi et al., 2024)
%                    'uniforme'-> cruce uniforme clasico
%   Mutacion       : inversion de bits (prob. pm por gen).
%   Reparacion     : agrega antenas (voraz/GRASP) hasta cubrir todo y elimina redundantes.
%   Busqueda local : "quitar y reparar" (drop & repair) sobre cada nuevo mejor individuo
%                    y sobre una fraccion pLS de los hijos (algoritmo memetico).
%   Reemplazo      : generacional con elitismo.
%   Diversificacion: reinicios parciales (se conserva la mejor solucion) al estancarse.
%   Parada         : maxGen, tiempoMax, objetivo, reinicios agotados o mejora relativa
%                    minima (tolMejora en una ventana de generaciones).
%
%   Parametros (struct p, todos opcionales; ver completar_parametros):
%     popSize(100) maxGen(2000) pc(0.9) pm(0.01) torneo(3) elite(5) paciencia(100)
%     maxReinicios(5) tiempoMax(Inf) objetivo(-Inf) semilla(1) cruce('fusion')
%     alphaInit([0 0.3]) alphaRep(0.05) busquedaLocal(true) pLS(0.1) maxPasLS(3)
%     tolMejora(0) ventana(100): parar si en las ultimas 'ventana' generaciones el
%       costo mejoro menos que tolMejora (relativo). Ej.: 1e-6 = 0.0001 %
%     onGen(@(gen,fBest,histBest) ...)  detenerFcn(@() logico)

    p = completar_parametros(p);
    [m, n] = size(A); %#ok<ASGLU>
    A = double(A);  c = c(:)';
    rng(p.semilla, 'twister');

    filasDe = cell(1, n);
    for j = 1:n, filasDe{j} = find(A(:, j)); end

    % ---------------- Poblacion inicial ----------------
    P   = false(p.popSize, n);
    for i = 1:p.popSize
        P(i, :) = individuo_nuevo(n, A, c, filasDe, p);
    end
    fit = P * c';
    evals = p.popSize;

    mejorHist = zeros(p.maxGen, 1);  mediaHist = zeros(p.maxGen, 1);
    peorHist  = zeros(p.maxGen, 1);  tiempoHist = zeros(p.maxGen, 1);
    reinicios = [];  nReinicios = 0;
    fBest = Inf;  xBest = [];  sinMejora = 0;  motivo = 'maxGen';  genFin = 1;
    t0 = tic;

    for gen = 1:p.maxGen
        genFin = gen;
        [fs, ord] = sort(fit);

        % Busqueda local sobre el mejor de la generacion si mejora al global
        if fs(1) < fBest - 1e-9 && p.busquedaLocal
            [xc, fc] = busqueda_local(P(ord(1), :), A, c, filasDe, p.maxPasLS);
            P(ord(1), :) = xc;  fit(ord(1)) = fc;
            [fs, ord] = sort(fit);
        end

        if fs(1) < fBest - 1e-9
            fBest = fs(1);  xBest = P(ord(1), :);  sinMejora = 0;
        else
            sinMejora = sinMejora + 1;
        end
        mejorHist(gen) = fBest;  mediaHist(gen) = mean(fit);
        peorHist(gen)  = fs(end);  tiempoHist(gen) = toc(t0);

        % ---- criterios de parada ----
        if fBest <= p.objetivo,            motivo = 'objetivo alcanzado'; break; end
        if p.tolMejora > 0 && gen > p.ventana
            mejoraRel = (mejorHist(gen-p.ventana) - mejorHist(gen)) / mejorHist(gen-p.ventana);
            if mejoraRel < p.tolMejora, motivo = 'mejora minima'; break; end
        end
        if tiempoHist(gen) >= p.tiempoMax, motivo = 'tiempo maximo';      break; end
        if ~isempty(p.detenerFcn) && p.detenerFcn(), motivo = 'detenido por usuario'; break; end
        if gen == p.maxGen, break; end

        % ---- reinicio parcial al estancarse ----
        if sinMejora >= p.paciencia
            if nReinicios >= p.maxReinicios
                motivo = 'reinicios agotados';  break;
            end
            nReinicios = nReinicios + 1;  reinicios(end+1) = gen; %#ok<AGROW>
            Pn = false(p.popSize, n);
            Pn(1, :) = xBest;
            for i = 2:p.popSize
                Pn(i, :) = individuo_nuevo(n, A, c, filasDe, p);
            end
            P = Pn;  fit = P * c';  evals = evals + p.popSize - 1;
            sinMejora = 0;
            continue;
        end

        % ---- elitismo ----
        nE = min(p.elite, p.popSize - 1);
        Pe = P(ord(1:nE), :);   fe = fs(1:nE);

        % ---- seleccion por torneo ----
        nHijos = p.popSize - nE;
        nPar   = ceil(nHijos / 2);
        i1 = torneo(fit, nPar, p.torneo);
        i2 = torneo(fit, nPar, p.torneo);
        P1 = P(i1, :);  P2 = P(i2, :);  f1 = fit(i1);  f2 = fit(i2);

        % ---- cruce ----
        switch p.cruce
            case 'fusion'      % Beasley y Chu (1996): el padre mejor aporta con mayor probabilidad
                pr = f2 ./ (f1 + f2);
                r1 = rand(nPar, n) < pr;   r2 = rand(nPar, n) < pr;
                O1 = P2;  O1(r1) = P1(r1);
                O2 = P2;  O2(r2) = P1(r2);
                alphaH = p.alphaRep;
            case 'union'       % Tayebi et al. (2024): union + minimalizacion
                O1 = P1 | P2;  O2 = O1;
                alphaH = max(p.alphaRep, 0.3);
            otherwise          % uniforme
                mk = rand(nPar, n) < 0.5;
                O1 = P1;  O1(mk) = P2(mk);
                O2 = P2;  O2(mk) = P1(mk);
                alphaH = p.alphaRep;
        end
        noCruce = rand(nPar, 1) >= p.pc;
        O1(noCruce, :) = P1(noCruce, :);
        O2(noCruce, :) = P2(noCruce, :);
        O = [O1; O2];  O = O(1:nHijos, :);

        % ---- mutacion (inversion de bits) ----
        O = xor(O, rand(size(O)) < p.pm);

        % ---- reparacion, busqueda local parcial y evaluacion ----
        fo = zeros(nHijos, 1);
        for k = 1:nHijos
            x = reparar(O(k, :), A, c, filasDe, alphaH, []);
            if p.busquedaLocal && rand < p.pLS
                x = busqueda_local(x, A, c, filasDe, 1);
            end
            O(k, :) = x;  fo(k) = c * x';
        end
        evals = evals + nHijos;

        P   = [Pe; O];
        fit = [fe; fo];

        if ~isempty(p.onGen), p.onGen(gen, fBest, mejorHist(1:gen)); end
    end

    info.mejorHist  = mejorHist(1:genFin);
    info.mediaHist  = mediaHist(1:genFin);
    info.peorHist   = peorHist(1:genFin);
    info.tiempoHist = tiempoHist(1:genFin);
    info.generaciones = genFin;
    info.evaluaciones = evals;
    info.reinicios = reinicios;
    info.tiempo = toc(t0);
    info.motivo = motivo;
    info.params = p;
    info.factible = all(A * double(xBest(:)) >= 1);
    info.nSel = nnz(xBest);
end

% =====================================================================
function x = individuo_nuevo(n, A, c, filasDe, p)
%INDIVIDUO_NUEVO  Solucion factible voraz aleatorizada (GRASP).
    alpha = p.alphaInit(1) + (p.alphaInit(2) - p.alphaInit(1)) * rand;
    x = reparar(false(1, n), A, c, filasDe, alpha, []);
end

function x = reparar(x, A, c, filasDe, alpha, prohibida)
%REPARAR  (1) Cubre clientes pendientes con la antena de menor costo/cobertura nueva
%         (alpha = 0: determinista; alpha > 0: lista restringida de candidatos, GRASP).
%         (2) Elimina antenas redundantes (de mayor a menor costo).
%         Si es imposible cubrir sin las antenas 'prohibida', devuelve [].
    n = numel(c);
    cnt = A * double(x(:));
    sinCub = (cnt == 0);
    while any(sinCub)
        gan = sum(A(sinCub, :), 1);
        ok = gan > 0;
        if ~isempty(prohibida), ok(prohibida) = false; end
        if ~any(ok), x = []; return; end
        razon = inf(1, n);
        razon(ok) = c(ok) ./ gan(ok);
        if alpha <= 0
            [~, j] = min(razon);
        else
            rmin = min(razon);  rmax = max(razon(ok));
            cand = find(razon <= rmin + alpha * (rmax - rmin));
            j = cand(randi(numel(cand)));
        end
        x(j) = true;
        cnt(filasDe{j}) = cnt(filasDe{j}) + 1;
        sinCub = (cnt == 0);
    end
    sel = find(x);
    clave = c(sel);
    if alpha > 0, clave = clave .* (1 + alpha * rand(size(clave))); end
    [~, o] = sort(clave, 'descend');
    sel = sel(o);
    for k = 1:numel(sel)
        j = sel(k);  r = filasDe{j};
        if all(cnt(r) >= 2)
            x(j) = false;  cnt(r) = cnt(r) - 1;
        end
    end
end

function [x, f] = busqueda_local(x, A, c, filasDe, maxPas)
%BUSQUEDA_LOCAL  Vecindario "quitar y reparar": se elimina una antena seleccionada,
%   se recubre de forma voraz sin ella y se acepta si el costo total baja.
    f = c * double(x(:));
    for pas = 1:maxPas
        mejoro = false;
        sel = find(x);
        [~, o] = sort(c(sel), 'descend');
        sel = sel(o);
        for k = 1:numel(sel)
            j = sel(k);
            if ~x(j), continue; end
            xt = x;  xt(j) = false;
            xt = reparar(xt, A, c, filasDe, 0, j);
            if isempty(xt), continue; end
            ft = c * double(xt(:));
            if ft < f - 1e-9
                x = xt;  f = ft;  mejoro = true;
            end
        end
        if ~mejoro, break; end
    end
end

function idx = torneo(fit, nSel, k)
%TORNEO  Seleccion por torneo de tamano k (minimizacion).
    N = numel(fit);
    cand = randi(N, nSel, k);
    [~, w] = min(fit(cand), [], 2);
    idx = cand(sub2ind(size(cand), (1:nSel)', w));
end

function p = completar_parametros(p)
    if nargin < 1 || isempty(p), p = struct(); end
    d = struct('popSize',100,'maxGen',2000,'pc',0.9,'pm',0.01,'torneo',3, ...
               'elite',5,'paciencia',100,'maxReinicios',5,'tiempoMax',Inf, ...
               'objetivo',-Inf,'semilla',1,'tolMejora',0,'ventana',100,'cruce','fusion','alphaInit',[0 0.3], ...
               'alphaRep',0.05,'busquedaLocal',true,'pLS',0.1,'maxPasLS',3, ...
               'onGen',[],'detenerFcn',[]);
    f = fieldnames(d);
    for i = 1:numel(f)
        if ~isfield(p, f{i}), p.(f{i}) = d.(f{i}); end
        if isempty(p.(f{i})) && ~any(strcmp(f{i}, {'onGen','detenerFcn'}))
            p.(f{i}) = d.(f{i});
        end
    end
end
