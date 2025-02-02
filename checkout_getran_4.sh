#!/bin/bash

# Ativa o modo "strict" no shell para tornar o script mais confiável,
# falhando se ocorrer erro em algum comando ou se alguma variável não estiver definida.
set -euo pipefail

##############################################################################
#                      VARIÁVEIS GLOBAIS DE CONFIGURAÇÃO                      #
##############################################################################

# Diretório base onde os arquivos de configuração IntelliJ ficam armazenados.
DIR_CONFIGURACAO="$HOME/apps/workspace-intellij-idea/2-dependencias/getran-configs-intellij-with-modules"

# Caminhos para os arquivos .iml específicos de cada módulo/projeto
ARQUIVO_SUTIL_IML="$DIR_CONFIGURACAO/sutil.iml"
ARQUIVO_GETRAN_IML="$DIR_CONFIGURACAO/getran.iml"
ARQUIVO_SNA_IML="$DIR_CONFIGURACAO/sna.iml"
ARQUIVO_TRRENAVAM_IML="$DIR_CONFIGURACAO/trrenavam.iml"

# Credenciais de acesso ao SVN
USUARIO_SVN="daniel.souza"
SENHA_SVN="detran123"

# Credenciais de acesso ao banco de dados
USUARIO_DB="danielsouza"
SENHA_DB="4633897dcf65664e2077226ac996ec32b2778cac"


##############################################################################
#                      FUNÇÃO PRINCIPAL: checkout_getran                      #
##############################################################################
# Responsável por:
#   1. Ler parâmetros de entrada (nome do projeto, tipo de projeto, ambiente).
#   2. Verificar se o diretório local existe e se o destino para o checkout
#      não está ocupado.
#   3. Garantir que as configurações (arquivos IntelliJ) estejam disponíveis.
#   4. Executar o checkout do código fonte de acordo com o tipo de projeto.
#   5. Ajustar configurações específicas (log4j, build, propriedades, etc.).
#   6. Baixar e configurar módulos adicionais (SNA, TRRENAVAM) conforme ambiente.
##############################################################################
checkout_getran() {
    # Parâmetros recebidos ou valores padrão
    local nome_do_projeto="${1:-getran}"
    local tipo_do_projeto="${2:-160}"
    local ambiente="${3:-dev}"

    # Determina o caminho local onde este script está sendo executado
    local caminho_local="$(dirname "$0")"

    # Determina o caminho final onde o checkout será armazenado
    local caminho_destino="$caminho_local/$nome_do_projeto"

    # Verifica se o diretório local do script existe
    if [ ! -d "$caminho_local" ]; then
        echo "Diretório local do projeto não existe. Operação cancelada."
        return 1
    fi

    # Verifica se o diretório de destino já está ocupado
    if [ -d "$caminho_destino" ]; then
        echo "O diretório de destino já existe. Operação cancelada."
        return 1
    fi

    # Garante que as configurações do IntelliJ estejam disponíveis;
    # caso não existam, faz o download do GitHub.
    verificar_ou_baixar_configuracoes

    # Seleciona o repositório de acordo com o tipo de projeto
    if [ "$tipo_do_projeto" = "160" ]; then
        realizar_checkout_svn "svn+ssh://$USUARIO_SVN@172.25.136.61/usr/svn/veiculo/branches/ISSUES 2023/balcaodigital_dev/getran" "$caminho_destino"
        realizar_checkout_sutil_balcao "$caminho_local"
    elif [ "$tipo_do_projeto" = "21" ]; then
        realizar_checkout_svn "svn+ssh://$USUARIO_SVN@172.25.136.61/usr/svn/veiculo/trunk/PROJETOS/getran" "$caminho_destino"
        realizar_checkout_sutil "$caminho_local"
    else
        echo "Tipo de projeto não suportado. Operação cancelada."
        return 1
    fi

    # Ajustes em arquivos de configuração do projeto principal
    alterar_log4j_xml "$caminho_destino/src/log4j.xml"
    alterar_build_xml "$caminho_destino/build.xml"
    alterar_build_properties "$caminho_destino/build.properties" "$nome_do_projeto"

    # (Opcional) Descomente a linha abaixo caso seja necessário alterar o facade da Nota Fiscal
    # alterar_nota_fiscal_facade "$caminho_destino/src/renavam/nfe/facadeImpl/NotaFiscalEletronicaFacadeImpl.java"

    # Copia configurações do IntelliJ para o projeto GETRAN
    cp -r "$DIR_CONFIGURACAO/.idea" "$caminho_destino/"
    cp "$ARQUIVO_GETRAN_IML" "$caminho_destino/"

    # Ajustes finais de acordo com o ambiente escolhido
    if [ "$ambiente" = "dev" ]; then
        alterar_context_xml "$caminho_destino/WebContent/META-INF/context.xml" "dev"
        alterar_sngmanager_properties "$caminho_destino/src/renavam/resources/transacoes/sngmanager.properties"
        realizar_checkout_sna_dev "$caminho_local"
        realizar_checkout_trrenavam_dev "$caminho_local"
        alterar_balcaodigital_properties "$caminho_destino/src/renavam/resources/api/balcaodigital.properties" "dev"
    elif [ "$ambiente" = "prod" ]; then
        alterar_context_xml "$caminho_destino/WebContent/META-INF/context.xml" "prod"
        realizar_checkout_sna_prod "$caminho_local"
        realizar_checkout_trrenavam_prod "$caminho_local"
        alterar_balcaodigital_properties "$caminho_destino/src/renavam/resources/api/balcaodigital.properties" "prod"
    else
        echo "Ambiente de projeto não suportado. Operação cancelada."
        return 1
    fi
}


##############################################################################
#         FUNÇÃO: verificar_ou_baixar_configuracoes                          #
##############################################################################
# Verifica se o diretório de configurações do IntelliJ (DIR_CONFIGURACAO)
# existe. Caso contrário, faz o download de um tar.gz do GitHub e o descompacta.
##############################################################################
verificar_ou_baixar_configuracoes() {
    if [ ! -d "$DIR_CONFIGURACAO" ]; then
        echo "Diretório $DIR_CONFIGURACAO não existe. Baixando o arquivo de configurações..."

        wget -c -O getran-configs-intellij-with-modules.tar.gz "https://github.com/danielsouzadetrance/getran-configs-intellij-with-modules/raw/refs/heads/main/getran-configs-intellij-with-modules.tar.gz"

        # Verifica se o arquivo foi baixado corretamente
        if [ ! -f "getran-configs-intellij-with-modules.tar.gz" ]; then
            echo "Falha no download do arquivo. Operação cancelada."
            exit 1
        fi

        # Cria o diretório de configurações e descompacta o arquivo
        mkdir -p "$DIR_CONFIGURACAO"
        tar -xzf "getran-configs-intellij-with-modules.tar.gz" -C "$DIR_CONFIGURACAO"
        echo "Arquivo de configurações descompactado em $DIR_CONFIGURACAO."
    fi
}


##############################################################################
#         FUNÇÃO: realizar_checkout_svn                                      #
##############################################################################
# Recebe a URL do repositório SVN e o caminho local para o checkout,
# executando o comando "svn checkout" usando sshpass (para passar a senha).
##############################################################################
realizar_checkout_svn() {
    local url_svn="$1"
    local destino="$2"

    sshpass -p "$SENHA_SVN" svn checkout "$url_svn" "$destino"
}


##############################################################################
#         FUNÇÃO: realizar_checkout_sutil_balcao                             #
##############################################################################
# Faz o checkout do módulo "sutil" (balcão) se ainda não existir no sistema.
# Exemplo de uso específico para a branch "balcaodigital_dev".
##############################################################################
realizar_checkout_sutil_balcao() {
    local caminho_local="$1"
    local caminho_sutil="$caminho_local/sutil"

    if [ ! -d "$caminho_sutil" ]; then
        realizar_checkout_svn "svn+ssh://$USUARIO_SVN@172.25.136.61/usr/svn/getranlibs/branches/ISSUES 2023/Sprint 01/balcao/sutil" "$caminho_sutil"
        cp "$ARQUIVO_SUTIL_IML" "$caminho_sutil/"
    fi
}


##############################################################################
#         FUNÇÃO: realizar_checkout_sutil                                    #
##############################################################################
# Faz o checkout do módulo "sutil" (trunk) se ainda não existir no sistema.
##############################################################################
realizar_checkout_sutil() {
    local caminho_local="$1"
    local caminho_sutil="$caminho_local/sutil"

    if [ ! -d "$caminho_sutil" ]; then
        realizar_checkout_svn "svn+ssh://$USUARIO_SVN@172.25.136.61/usr/svn/getranlibs/trunk/sutil" "$caminho_sutil"
        cp "$ARQUIVO_SUTIL_IML" "$caminho_sutil/"
    fi
}


##############################################################################
#         FUNÇÃO: alterar_context_xml                                        #
##############################################################################
# Recebe o caminho de um arquivo context.xml e o ambiente ("dev" ou "prod").
# Altera parâmetros de conexão (usuário, senha, pool) e, no caso de "dev",
# altera a URL para apontar para outro servidor.
##############################################################################
alterar_context_xml() {
    local arquivo="$1"
    local ambiente="${2:-}"

    # Ajusta credenciais do banco de dados
    sed -i "s/username=\"[^\"]*\"/username=\"$USUARIO_DB\"/g" "$arquivo"
    sed -i "s/password=\"[^\"]*\"/password=\"$SENHA_DB\"/g" "$arquivo"

    # Ajustes nas propriedades do pool
    sed -i "s/initialSize=\"[^\"]*\"/initialSize=\"2\"/g" "$arquivo"
    sed -i "s/maxActive=\"[^\"]*\"/maxActive=\"2\"/g" "$arquivo"
    sed -i "s/maxIdle=\"[^\"]*\"/maxIdle=\"2\"/g" "$arquivo"

    # Se for ambiente de desenvolvimento, altera a URL do banco
    if [ "$ambiente" = "dev" ]; then
        sed -i 's/url="jdbc:postgresql:\/\/172.25.136.30:5432\/dbveiculos_dev"/url="jdbc:postgresql:\/\/172.25.136.81:5432\/dbveiculos_dev"/g' "$arquivo"
    fi
}


##############################################################################
#         FUNÇÃO: alterar_log4j_xml                                          #
##############################################################################
# Altera o nível de prioridade do log4j para "debug" no lugar de "error".
##############################################################################
alterar_log4j_xml() {
    local arquivo="$1"
    sed -i 's/<priority value="error" \/>/<priority value="debug" \/>/g' "$arquivo"
}


##############################################################################
#         FUNÇÃO: alterar_build_xml                                          #
##############################################################################
# Comenta a linha <eclipse.refreshLocal> do build.xml, que poderia causar
# conflitos ou lentidão em alguns ambientes.
##############################################################################
alterar_build_xml() {
    local arquivo="$1"
    sed -i 's/<eclipse.refreshLocal resource="@{projeto}" depth="infinite" \/>/<!--<eclipse.refreshLocal resource="@{projeto}" depth="infinite" \/>-->/g' "$arquivo"
}


##############################################################################
#         FUNÇÃO: alterar_nota_fiscal_facade                                 #
##############################################################################
# Opcionalmente comenta a linha "loadService();" dentro da facade de NFE,
# caso haja necessidade de desabilitar esse carregamento de serviço.
##############################################################################
alterar_nota_fiscal_facade() {
    local arquivo="$1"
    sed -i 's/loadService();/\/\/loadService();/g' "$arquivo"
}


##############################################################################
#         FUNÇÃO: alterar_build_properties                                   #
##############################################################################
# Substitui o valor de "getran.project.name" pelo nome do projeto desejado,
# garantindo que o build.properties fique alinhado com o nome correto.
##############################################################################
alterar_build_properties() {
    local arquivo="$1"
    local nome_do_projeto="$2"

    sed -i "s/getran.project.name=[^[:space:]]*/getran.project.name=$nome_do_projeto/g" "$arquivo"
}


##############################################################################
#         FUNÇÃO: alterar_sngmanager_properties                              #
##############################################################################
# Ativa a porta 16504 e comenta a 16505 no arquivo sngmanager.properties,
# tipicamente usado em ambiente de desenvolvimento.
##############################################################################
alterar_sngmanager_properties() {
    local arquivo="$1"

    # Ativa a porta 16504
    sed -i 's/#SNG.Gateway.port=16504/SNG.Gateway.port=16504/g' "$arquivo"

    # Comenta a porta 16505
    sed -i 's/SNG.Gateway.port=16505/#SNG.Gateway.port=16505/g' "$arquivo"
}


##############################################################################
#         FUNÇÕES DE CHECKOUT E AJUSTE PARA O MÓDULO SNA                     #
##############################################################################

# Ambiente Dev
realizar_checkout_sna_dev() {
    local caminho_local="$1"
    local caminho_sna="$caminho_local/sna"

    if [ ! -d "$caminho_sna" ]; then
        realizar_checkout_svn "svn+ssh://$USUARIO_SVN@172.25.136.61/usr/svn/veiculo/trunk/PROJETOS/sna" "$caminho_sna"
        alterar_sna_config "$caminho_sna/web/WEB-INF/config.properties" "dev"
        alterar_context_xml "$caminho_sna/web/META-INF/context.xml" "dev"
        cp "$ARQUIVO_SNA_IML" "$caminho_sna/"
    fi
}

# Ambiente Prod
realizar_checkout_sna_prod() {
    local caminho_local="$1"
    local caminho_sna="$caminho_local/sna"

    if [ ! -d "$caminho_sna" ]; then
        realizar_checkout_svn "svn+ssh://$USUARIO_SVN@172.25.136.61/usr/svn/veiculo/trunk/PROJETOS/sna" "$caminho_sna"
        alterar_sna_config "$caminho_sna/web/WEB-INF/config.properties" "prod"
        alterar_context_xml "$caminho_sna/web/META-INF/context.xml" "prod"
        cp "$ARQUIVO_SNA_IML" "$caminho_sna/"
    fi
}


##############################################################################
#         FUNÇÃO: alterar_sna_config                                         #
##############################################################################
# Altera o arquivo config.properties do SNA, ajustando nome de usuário,
# senha, número máximo de conexões e a URL do banco (caso dev).
##############################################################################
alterar_sna_config() {
    local arquivo="$1"
    local ambiente="$2"

    # Ajusta credenciais e maxConnections
    sed -i "s/^jdbc\/default\/username=.*/jdbc\/default\/username=$USUARIO_DB/" "$arquivo"
    sed -i "s/^jdbc\/default\/password=.*/jdbc\/default\/password=$SENHA_DB/" "$arquivo"
    sed -i "s/^jdbc\/default\/maxConnections=.*/jdbc\/default\/maxConnections=2/" "$arquivo"

    # Se for ambiente dev, muda a URL para o servidor de desenvolvimento
    if [ "$ambiente" = "dev" ]; then
        sed -i 's#^jdbc/default/connectionURL=.*#jdbc/default/connectionURL=jdbc:postgresql://172.25.136.81:5432/dbveiculos_dev#' "$arquivo"
    fi
}


##############################################################################
#         FUNÇÕES DE CHECKOUT E AJUSTE PARA O MÓDULO TRRENAVAM               #
##############################################################################

# Ambiente Dev
realizar_checkout_trrenavam_dev() {
    local caminho_local="$1"
    local caminho_trrenavam="$caminho_local/trrenavam"

    if [ ! -d "$caminho_trrenavam" ]; then
        realizar_checkout_svn "svn+ssh://$USUARIO_SVN@172.25.136.61/usr/svn/veiculo/trunk/MODULOS/trrenavam" "$caminho_trrenavam"
        alterar_trrenavam_config "$caminho_trrenavam/src/configTransacoes/config.properties" "dev"
        alterar_trrenavam_sql_map_config "$caminho_trrenavam/src/montreal/resources/maps/SqlMapConfig.xml" "dev"
        alterar_trrenavam_connection_pool "$caminho_trrenavam/src/montreal/str/banco/ConnectionPool.java" "dev"
        alterar_trrenavam_transacoes_socket "$caminho_trrenavam/src/montreal/str/trenvio/comunicacao/TransacoesSocket.java" "dev"
        alterar_trrenavam_config_transacoes "$caminho_trrenavam/src/renavam/resources/transacoes/config.properties" "dev"
        alterar_sngmanager_properties "$caminho_trrenavam/src/renavam/resources/transacoes/sngmanager.properties"
        cp "$ARQUIVO_TRRENAVAM_IML" "$caminho_trrenavam/"
    fi
}

# Ambiente Prod
realizar_checkout_trrenavam_prod() {
    local caminho_local="$1"
    local caminho_trrenavam="$caminho_local/trrenavam"

    if [ ! -d "$caminho_trrenavam" ]; then
        realizar_checkout_svn "svn+ssh://$USUARIO_SVN@172.25.136.61/usr/svn/veiculo/trunk/MODULOS/trrenavam" "$caminho_trrenavam"
        alterar_trrenavam_config "$caminho_trrenavam/src/configTransacoes/config.properties" "prod"
        alterar_trrenavam_sql_map_config "$caminho_trrenavam/src/montreal/resources/maps/SqlMapConfig.xml" "prod"
        alterar_trrenavam_connection_pool "$caminho_trrenavam/src/montreal/str/banco/ConnectionPool.java" "prod"
        alterar_trrenavam_config_transacoes "$caminho_trrenavam/src/renavam/resources/transacoes/config.properties" "prod"
        cp "$ARQUIVO_TRRENAVAM_IML" "$caminho_trrenavam/"
    fi
}


##############################################################################
#         FUNÇÕES ESPECÍFICAS DE CONFIGURAÇÃO DO TRRENAVAM                   #
##############################################################################

# Altera config.properties principal (pool de conexões, URL) conforme ambiente
alterar_trrenavam_config() {
    local arquivo="$1"
    local ambiente="$2"

    # Ajusta parâmetros do pool de conexões
    sed -i "s/^maxActive=[^ ]*/maxActive=2/" "$arquivo"
    sed -i "s/^maxIdle=[^ ]*/maxIdle=2/" "$arquivo"
    sed -i "s/^minIdle=[^ ]*/minIdle=2/" "$arquivo"

    # Ajusta URL em ambiente de desenvolvimento
    if [ "$ambiente" = "dev" ]; then
        sed -i 's#^url-conexao = jdbc:postgresql://172.25.136.30:5432/db_veiculos_dev#url-conexao = jdbc:postgresql://172.25.136.81:5432/db_veiculos_dev#' "$arquivo"
    fi
}

# Ajusta credenciais e URL no SqlMapConfig.xml
alterar_trrenavam_sql_map_config() {
    local arquivo="$1"
    local ambiente="$2"

    # Ajusta usuário e senha
    sed -i "s#<property name=\"username\" value=\"[^\"]*\" />#<property name=\"username\" value=\"$USUARIO_DB\" />#" "$arquivo"
    sed -i "s#<property name=\"password\" value=\"[^\"]*\" />#<property name=\"password\" value=\"$SENHA_DB\" />#" "$arquivo"
    sed -i 's#<property name="maxActive" value="[^"]*" />#<property name="maxActive" value="2" />#' "$arquivo"

    # Em ambiente dev, muda a URL
    if [ "$ambiente" = "dev" ]; then
        sed -i 's#<property name="url" value="jdbc:postgresql://172.25.136.30:5432/dbveiculos_dev" />#<property name="url" value="jdbc:postgresql://172.25.136.81:5432/dbveiculos_dev" />#' "$arquivo"
    fi
}

# Ajusta parâmetros do ConnectionPool.java
alterar_trrenavam_connection_pool() {
    local arquivo="$1"
    local ambiente="$2"

    # Em ambiente dev, muda a URL do banco
    if [ "$ambiente" = "dev" ]; then
        sed -i 's#String url = "jdbc:postgresql://172.25.136.30:5432/dbveiculos_dev";#String url = "jdbc:postgresql://172.25.136.81:5432/dbveiculos_dev";#' "$arquivo"
    fi

    # Ajusta credenciais e limita conexões
    sed -i 's#this.ds.setUsername( *"[^"]*" *);#this.ds.setUsername( "'$USUARIO_DB'" );#' "$arquivo"
    sed -i 's#this.ds.setPassword( String.valueOf(this.[^)]*) );#this.ds.setPassword( "'$SENHA_DB'" );#' "$arquivo"
    sed -i 's#this.ds.setMaxActive( [^)]* );#this.ds.setMaxActive( 1 );#' "$arquivo"
    sed -i 's#this.ds.setMaxIdle( [^)]* );#this.ds.setMaxIdle( 1 );#' "$arquivo"
    sed -i 's#this.ds.setMinIdle( [^)]* );#this.ds.setMinIdle( 1 );#' "$arquivo"
}

# Ajusta a classe TransacoesSocket.java para usar HOST de homologação em "dev"
alterar_trrenavam_transacoes_socket() {
    local arquivo="$1"
    local ambiente="$2"

    if [ "$ambiente" = "dev" ]; then
        sed -i 's#this.host = HostIP.PRODUCAO;#this.host = HostIP.HOMOLOGACAO;#' "$arquivo"
    fi
}

# Ajusta config.properties de transações (pool e URL)
alterar_trrenavam_config_transacoes() {
    local arquivo="$1"
    local ambiente="$2"

    # Ajusta parâmetros de pool
    sed -i "s/^maxActive=[^ ]*/maxActive=2/" "$arquivo"
    sed -i "s/^maxIdle=[^ ]*/maxIdle=2/" "$arquivo"
    sed -i "s/^minIdle=[^ ]*/minIdle=2/" "$arquivo"

    # Em ambiente dev, muda a URL do banco
    if [ "$ambiente" = "dev" ]; then
        sed -i 's/url-conexao = jdbc:postgresql:\/\/172.25.136.30:5432\/dbveiculos_dev/url-conexao = jdbc:postgresql:\/\/172.25.136.81:5432\/dbveiculos_dev/g' "$arquivo"
    fi
}


##############################################################################
#         FUNÇÃO: alterar_balcaodigital_properties                           #
##############################################################################
# Se o arquivo balcaodigital.properties existir, ajusta a linha "env=..."
# para o ambiente atual (dev ou prod).
##############################################################################
alterar_balcaodigital_properties() {
    local arquivo="$1"
    local ambiente="$2"

    if [ -f "$arquivo" ]; then
        sed -i "s/env=prod/env=$ambiente/g" "$arquivo"
    fi
}


##############################################################################
#              CHAMADA DA FUNÇÃO PRINCIPAL COM OS PARÂMETROS                 #
##############################################################################
checkout_getran "$@"
