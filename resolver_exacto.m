function res = resolver_exacto(A, c, opc)
%RESOLVER_EXACTO  Resuelve el SET COVER ponderado con intlinprog (Branch & Bound / Cut).
%
%   min  sum_j c_j x_j
%   s.a. sum_j a_ij x_j >= 1   para todo cliente i
%        x_j en {0,1}
%
%   opc (struct, opcional):
%       .tiempoMax  limite de tiempo [s]                        (default 28800 = 8 h)
%       .tolRel     brecha relativa aceptada para detenerse     (default 1e-3 = 0.1 %)
%       .tolAbs     brecha absoluta aceptada                    (default 0.99)
%                   Con costos enteros, una brecha absoluta < 1 ya prueba optimalidad.
%       .display    'off' | 'final' | 'iter'                    (default 'iter')
%       .x0         solucion inicial factible (1 x n) = arranque en caliente (opcional)
%
%   res (struct): x, fval, seleccion, nSel, tiempo, exitflag, mensaje, zLP, cota,
%                 gapAbs, gapRel, gapPct, nodos, factible, optimo, estado

    if nargin < 3, opc = struct(); end
    if ~isfield(opc,'tiempoMax'), opc.tiempoMax = 28800;  end
    if ~isfield(opc,'tolRel'),    opc.tolRel    = 1e-3;   end
    if ~isfield(opc,'tolAbs'),    opc.tolAbs    = 0.99;   end
    if ~isfield(opc,'display'),   opc.display   = 'iter'; end
    if ~isfield(opc,'x0'),        opc.x0        = [];     end

    [m, n] = size(A);
    f      = c(:);
    intcon = 1:n;
    Aineq  = -sparse(A);          % -A x <= -1   <=>   A x >= 1
    bineq  = -ones(m, 1);
    lb     = zeros(n, 1);
    ub     = ones(n, 1);

    % tolAbs < 1 solo es valido si todos los costos son enteros
    if any(abs(c - round(c)) > 1e-9), opc.tolAbs = 1e-6; end

    % ---- Relajacion lineal (cota inferior del optimo) ----
    zLP = NaN;
    try
        optLP = optimoptions('linprog', 'Display', 'off');
        [~, zLP] = linprog(f, Aineq, bineq, [], [], lb, ub, optLP);
    catch
    end
    if strcmp(opc.display,'iter') || strcmp(opc.display,'final')
        fprintf('  Cota inferior (relajacion LP): %.2f\n', zLP);
    end

    % ---- Problema entero ----
    opt = optimoptions('intlinprog', ...
        'Display', opc.display, ...
        'MaxTime', opc.tiempoMax, ...
        'RelativeGapTolerance', opc.tolRel, ...
        'AbsoluteGapTolerance', opc.tolAbs);

    x0 = [];
    if ~isempty(opc.x0), x0 = double(opc.x0(:)); end

    tic;
    [x, fval, exitflag, output] = intlinprog(f, intcon, Aineq, bineq, [], [], lb, ub, x0, opt);
    tiempo = toc;

    res.tiempo   = tiempo;
    res.exitflag = exitflag;
    res.mensaje  = output.message;
    res.zLP      = zLP;
    res.nodos    = NaN;  res.gapAbs = NaN;  res.gapRel = NaN;
    if isfield(output, 'numnodes'),    res.nodos  = output.numnodes;    end
    if isfield(output, 'absolutegap'), res.gapAbs = output.absolutegap; end
    if isfield(output, 'relativegap'), res.gapRel = output.relativegap; end

    if isempty(x)
        res.x = []; res.fval = NaN; res.seleccion = []; res.nSel = 0; res.cota = zLP;
        res.gapPct = NaN; res.factible = false; res.optimo = false;
        res.estado = 'Sin solucion entera factible encontrada';
        return;
    end

    x = round(x(:)') > 0;                      % limpiar ruido numerico
    res.x         = x;
    res.fval      = c(:)' * x(:);
    res.seleccion = find(x);
    res.nSel      = nnz(x);
    res.factible  = all(A * double(x(:)) >= 1);

    % Mejor cota inferior disponible y brecha real respecto a ella
    cota = zLP;
    if ~isnan(res.gapAbs), cota = max(zLP, res.fval - res.gapAbs); end
    if all(abs(c - round(c)) < 1e-9), cota = ceil(cota - 1e-9); end   % costos enteros
    res.cota   = cota;
    res.gapPct = 100 * (res.fval - cota) / res.fval;

    res.optimo = (exitflag == 1) && (res.gapPct <= 100*opc.tolRel + 1e-9);
    if res.gapPct < 1e-9
        res.estado = 'Optimo comprobado (brecha = 0)';
    elseif res.optimo
        res.estado = sprintf('Optimo dentro de la tolerancia (brecha <= %.3f %%)', res.gapPct);
    elseif exitflag == 0
        res.estado = sprintf('Limite de tiempo: mejor solucion hallada, a %.3f %% de la cota', res.gapPct);
    else
        res.estado = sprintf('Terminado con brecha de %.3f %% respecto a la cota', res.gapPct);
    end
end
