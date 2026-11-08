function [A, c, m, n] = cargar_datos(archivoCSV, archivoXLSX)
%CARGAR_DATOS  Lee la matriz de cobertura y el vector de costos del proyecto.
%   [A,c,m,n] = cargar_datos(archivoCSV, archivoXLSX)
%   A : matriz binaria m x n (filas = clientes, columnas = antenas)
%   c : vector fila 1 x n con el costo de cada antena
%
%   Los archivos se buscan automaticamente en:
%     1) la ruta indicada (si es completa),
%     2) la MISMA CARPETA donde estan estos archivos .m,
%     3) la carpeta actual de MATLAB,
%     4) si no aparecen, se abre una ventana para elegirlos.
%
%   Formato esperado:
%   - set_cover_500x500.csv : 1a fila = encabezado (0..499), luego 500 filas de 0/1.
%   - Costo_S.xlsx          : fila 2, celdas B2:SG2 = costos de las 500 antenas.

    if nargin < 1, archivoCSV  = 'set_cover_500x500.csv'; end
    if nargin < 2, archivoXLSX = 'Costo_S.xlsx';          end

    archivoCSV  = ubicar(archivoCSV,  '*.csv',  'Seleccione la matriz de cobertura (CSV)');
    archivoXLSX = ubicar(archivoXLSX, '*.xlsx', 'Seleccione el archivo de costos (XLSX)');
    fprintf('Leyendo:\n  %s\n  %s\n', archivoCSV, archivoXLSX);

    % --- Matriz de cobertura (se omite la fila de encabezado numerico) ---
    A = readmatrix(archivoCSV, 'NumHeaderLines', 1);
    A(isnan(A)) = 0;
    A = double(A ~= 0);

    % --- Vector de costos (tres intentos, de mas a menos especifico) ---
    c = [];
    try
        c = readmatrix(archivoXLSX, 'Range', 'B2:SG2');
    catch
    end
    if isempty(c) || all(isnan(c))
        try
            raw = readmatrix(archivoXLSX);          % toda la hoja
            c = raw(2, 2:end);
        catch
        end
    end
    if isempty(c) || all(isnan(c))
        try
            raw = readcell(archivoXLSX);            % ultimo recurso
            fila = raw(2, 2:end);
            c = cellfun(@numOrNan, fila);
        catch ME
            error('cargar_datos:xlsx', ...
                ['No se pudo leer %s.\nCierre el archivo si esta abierto en Excel y ' ...
                 'verifique que los costos esten en la fila 2 (B2:SG2).\nDetalle: %s'], ...
                archivoXLSX, ME.message);
        end
    end
    c = c(:)';
    c = c(~isnan(c));

    [m, n] = size(A);

    % --- Validaciones ---
    if numel(c) ~= n
        error('cargar_datos:dim', ...
            'El numero de costos (%d) no coincide con el numero de antenas (%d).', numel(c), n);
    end
    if any(c <= 0)
        error('cargar_datos:costos', 'El vector de costos contiene valores no positivos.');
    end
    if any(sum(A, 2) == 0)
        error('cargar_datos:infactible', ...
            'Hay clientes que ninguna antena cubre: el problema es infactible.');
    end
end

function ruta = ubicar(archivo, filtro, titulo)
%UBICAR  Devuelve la ruta completa del archivo buscandolo en varias carpetas.
    [~, ~, ext] = fileparts(archivo);
    carpetaCodigo = fileparts(mfilename('fullpath'));
    candidatos = {archivo, fullfile(carpetaCodigo, archivo), fullfile(pwd, archivo)};
    for k = 1:numel(candidatos)
        if isfile(candidatos{k})
            ruta = candidatos{k};
            % obtener ruta absoluta
            info = dir(ruta);
            ruta = fullfile(info(1).folder, info(1).name);
            return;
        end
    end
    % No se encontro: pedirlo al usuario
    [a, b] = uigetfile(filtro, titulo);
    if isequal(a, 0)
        error('cargar_datos:archivo', 'No se encontro el archivo %s%s.', archivo, '');
    end
    ruta = fullfile(b, a);
end

function v = numOrNan(x)
    if isnumeric(x) && isscalar(x), v = double(x); else, v = NaN; end
end
