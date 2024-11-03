#!/bin/bash

checkout_getran() {
    local local_projeto="$(dirname "$0")"
    local nome_projeto="${1:-getran}"
    local caminho="$local_projeto/$nome_projeto"
    local tipo_projeto="${2:-160}"
    local ambiente="${3:-dev}"

    # Configuration paths
    local config_dir="$HOME/apps/workspace-intellij-idea/2-dependencias/getran-configs-intellij-with-modules"
    local sutil_iml="$config_dir/sutil.iml"
    local getran_iml="$config_dir/getran.iml"
    local sna_iml="$config_dir/sna.iml"
    local trrenavam_iml="$config_dir/trrenavam.iml"

    #dados do usuario
    local user_svn="daniel.souza"
    local pwd_svn="detran123"
    local user_db="danielsouza"
    local pwd_db="4633897dcf65664e2077226ac996ec32b2778cac"

    # Check if the local project directory exists
    if [ ! -d "$local_projeto" ]; then
        echo "Local do projeto nao existe. Operacao cancelada."
        return 1
    fi

    # Check if the destination directory already exists
    if [ -d "$caminho" ]; then
        echo "O diretorio de destino ja existe. Operacao cancelada."
        return 1
    fi

    # Verifica se o diretório de configuração já existe
    if [ ! -d "$config_dir" ]; then
        echo "Diretório $config_dir não existe. Baixando o arquivo."

        # Baixar o arquivo do GitHub
        wget -c -O getran-configs-intellij-with-modules.tar.gz "https://github.com/danielsouzadetrance/getran-configs-intellij-with-modules/raw/refs/heads/main/getran-configs-intellij-with-modules.tar.gz"

        # Verifica se o arquivo foi baixado com sucesso
        if [ ! -f "getran-configs-intellij-with-modules.tar.gz" ]; then
            echo "Falha no download do arquivo. Operação cancelada."
            exit 1
        fi

        # Cria o diretório de destino
        mkdir -p "$config_dir"

        # Descompacta o arquivo no diretório criado
        tar -xzf "getran-configs-intellij-with-modules.tar.gz" -C "$config_dir"

        echo "Arquivo descompactado em $config_dir."
    fi

    # Perform SVN checkout based on project type
    if [ "$tipo_projeto" = "160" ]; then
        checkout_svn "svn+ssh://$user_svn@172.25.136.61/usr/svn/veiculo/branches/ISSUES 2023/balcaodigital_dev/getran" "$caminho"
        checkout_sutil_balcao
    elif [ "$tipo_projeto" = "21" ]; then
        checkout_svn "svn+ssh://$user_svn@172.25.136.61/usr/svn/veiculo/trunk/PROJETOS/getran" "$caminho"
        checkout_sutil
    else
        echo "Tipo de projeto nao suportado. Operacao cancelada."
        return 1
    fi

    # Modify project files
    modify_log4j_xml "$caminho/src/log4j.xml"
    modify_build_xml "$caminho/build.xml"
    modify_build_properties "$caminho/build.properties" "$nome_projeto"

    ## esse comando abaixo altera o acesso da nota fiscal pra quem nao tem acesso.
    # modify_nota_fiscal_facade "$caminho/src/renavam/nfe/facadeImpl/NotaFiscalEletronicaFacadeImpl.java"
    

    # Copy configuration files
    cp -r "$config_dir/.idea" "$caminho/"
    cp "$getran_iml" "$caminho/"

    # Handle environment-specific configurations
    if [ "$ambiente" = "dev" ]; then
        modify_context_xml "$caminho/WebContent/META-INF/context.xml" "dev"
        modify_sngmanager_properties "$caminho/src/renavam/resources/transacoes/sngmanager.properties"
        checkout_sna_dev
        checkout_trrenavam_dev
        modify_balcaodigital_properties "$caminho/src/renavam/resources/api/balcaodigital.properties" "dev"
    elif [ "$ambiente" = "prod" ]; then
        modify_context_xml "$caminho/WebContent/META-INF/context.xml" "prod"
        checkout_sna_prod
        checkout_trrenavam_prod
        modify_balcaodigital_properties "$caminho/src/renavam/resources/api/balcaodigital.properties" "prod"
    else
        echo "Ambiente de projeto nao suportado. Operacao cancelada."
        return 1
    fi
}

checkout_svn() {
    local url="$1"
    local dest="$2"
    sshpass -p "$pwd_svn" svn checkout "$url" "$dest"
}

checkout_sutil_balcao() {
    if [ ! -d "$local_projeto/sutil" ]; then
        checkout_svn "svn+ssh://$user_svn@172.25.136.61/usr/svn/getranlibs/branches/ISSUES 2023/Sprint 01/balcao/sutil" "$local_projeto/sutil"
        cp "$sutil_iml" "$local_projeto/sutil/"
    fi
}

checkout_sutil() {
    if [ ! -d "$local_projeto/sutil" ]; then
        checkout_svn "svn+ssh://$user_svn@172.25.136.61/usr/svn/getranlibs/trunk/sutil" "$local_projeto/sutil"
        cp "$sutil_iml" "$local_projeto/sutil/"
    fi
}

modify_context_xml() {
    local file="$1"
    local env="${2:-}"
    sed -i "s/username=\"[^\"]*\"/username=\"$user_db\"/g" "$file"
    sed -i "s/password=\"[^\"]*\"/password=\"$pwd_db\"/g" "$file"
    sed -i "s/initialSize=\"[^\"]*\"/initialSize=\"2\"/g" "$file"
    sed -i "s/maxActive=\"[^\"]*\"/maxActive=\"2\"/g" "$file"
    sed -i "s/maxIdle=\"[^\"]*\"/maxIdle=\"2\"/g" "$file"
    if [ "$env" = "dev" ]; then
        sed -i 's/url="jdbc:postgresql:\/\/172.25.136.30:5432\/dbveiculos_dev"/url="jdbc:postgresql:\/\/172.25.136.81:5432\/dbveiculos_dev"/g' "$file"
    fi
}

modify_log4j_xml() {
    local file="$1"
    sed -i 's/<priority value="error" \/>/<priority value="debug" \/>/g' "$file"
}

modify_build_xml() {
    local file="$1"
    sed -i 's/<eclipse.refreshLocal resource="@{projeto}" depth="infinite" \/>/<!--<eclipse.refreshLocal resource="@{projeto}" depth="infinite" \/>-->/g' "$file"
}

modify_nota_fiscal_facade() {
    local file="$1"
    sed -i 's/loadService();/\/\/loadService();/g' "$file"
}

modify_build_properties() {
    local file="$1"
    local project_name="$2"
    sed -i "s/getran.project.name=[^[:space:]]*/getran.project.name=$project_name/g" "$file"
}

modify_sngmanager_properties() {
    local file="$1"
    sed -i 's/#SNG.Gateway.port=16504/SNG.Gateway.port=16504/g' "$file"
    sed -i 's/SNG.Gateway.port=16505/#SNG.Gateway.port=16505/g' "$file"
}

checkout_sna_dev() {
    if [ ! -d "$local_projeto/sna" ]; then
        checkout_svn "svn+ssh://$user_svn@172.25.136.61/usr/svn/veiculo/trunk/PROJETOS/sna" "$local_projeto/sna"
        modify_sna_config "$local_projeto/sna/web/WEB-INF/config.properties" "dev"
        modify_context_xml "$local_projeto/sna/web/META-INF/context.xml" "dev"
        cp "$sna_iml" "$local_projeto/sna/"
    fi
}

checkout_sna_prod() {
    if [ ! -d "$local_projeto/sna" ]; then
        checkout_svn "svn+ssh://$user_svn@172.25.136.61/usr/svn/veiculo/trunk/PROJETOS/sna" "$local_projeto/sna"
        modify_sna_config "$local_projeto/sna/web/WEB-INF/config.properties" "prod"
        modify_context_xml "$local_projeto/sna/web/META-INF/context.xml" "prod"
        cp "$sna_iml" "$local_projeto/sna/"
    fi
}

modify_sna_config() {
    local file="$1"
    local env="$2"
    sed -i "s/^jdbc\/default\/username=.*/jdbc\/default\/username=$user_db/" "$file"
    sed -i "s/^jdbc\/default\/password=.*/jdbc\/default\/password=$pwd_db/" "$file"
    sed -i "s/^jdbc\/default\/maxConnections=.*/jdbc\/default\/maxConnections=2/" "$file"
    if [ "$env" = "dev" ]; then
        sed -i 's#^jdbc/default/connectionURL=.*#jdbc/default/connectionURL=jdbc:postgresql://172.25.136.81:5432/dbveiculos_dev#' "$file"
    fi
}

checkout_trrenavam_dev() {
    if [ ! -d "$local_projeto/trrenavam" ]; then
        checkout_svn "svn+ssh://$user_svn@172.25.136.61/usr/svn/veiculo/trunk/MODULOS/trrenavam" "$local_projeto/trrenavam"
        modify_trrenavam_config "$local_projeto/trrenavam/src/configTransacoes/config.properties" "dev"
        modify_trrenavam_sql_map_config "$local_projeto/trrenavam/src/montreal/resources/maps/SqlMapConfig.xml" "dev"
        modify_trrenavam_connection_pool "$local_projeto/trrenavam/src/montreal/str/banco/ConnectionPool.java" "dev"
        modify_trrenavam_transacoes_socket "$local_projeto/trrenavam/src/montreal/str/trenvio/comunicacao/TransacoesSocket.java" "dev"
        modify_trrenavam_config_transacoes "$local_projeto/trrenavam/src/renavam/resources/transacoes/config.properties" "dev"
        modify_sngmanager_properties "$local_projeto/trrenavam/src/renavam/resources/transacoes/sngmanager.properties"
        cp "$trrenavam_iml" "$local_projeto/trrenavam/"
    fi
}

checkout_trrenavam_prod() {
    if [ ! -d "$local_projeto/trrenavam" ]; then
        checkout_svn "svn+ssh://$user_svn@172.25.136.61/usr/svn/veiculo/trunk/MODULOS/trrenavam" "$local_projeto/trrenavam"
        modify_trrenavam_config "$local_projeto/trrenavam/src/configTransacoes/config.properties" "prod"
        modify_trrenavam_sql_map_config "$local_projeto/trrenavam/src/montreal/resources/maps/SqlMapConfig.xml" "prod"
        modify_trrenavam_connection_pool "$local_projeto/trrenavam/src/montreal/str/banco/ConnectionPool.java" "prod"
        modify_trrenavam_config_transacoes "$local_projeto/trrenavam/src/renavam/resources/transacoes/config.properties" "prod"
        cp "$trrenavam_iml" "$local_projeto/trrenavam/"
    fi
}

modify_trrenavam_config() {
    local file="$1"
    local env="$2"
    sed -i "s/^maxActive=[^ ]*/maxActive=2/" "$file"
    sed -i "s/^maxIdle=[^ ]*/maxIdle=2/" "$file"
    sed -i "s/^minIdle=[^ ]*/minIdle=2/" "$file"
    if [ "$env" = "dev" ]; then
        sed -i 's#^url-conexao = jdbc:postgresql://172.25.136.30:5432/db_veiculos_dev#url-conexao = jdbc:postgresql://172.25.136.81:5432/db_veiculos_dev#' "$file"
    fi
}

modify_trrenavam_sql_map_config() {
    local file="$1"
    local env="$2"

    sed -i "s#<property name=\"username\" value=\"[^\"]*\" />#<property name=\"username\" value=\"$user_db\" />#" "$file"
    sed -i "s#<property name=\"password\" value=\"[^\"]*\" />#<property name=\"password\" value=\"$pwd_db\" />#" "$file"
    sed -i 's#<property name="maxActive" value="[^"]*" />#<property name="maxActive" value="2" />#' "$file"

    if [ "$env" = "dev" ]; then
        sed -i 's#<property name="url" value="jdbc:postgresql://172.25.136.30:5432/dbveiculos_dev" />#<property name="url" value="jdbc:postgresql://172.25.136.81:5432/dbveiculos_dev" />#' "$file"
    fi
}

modify_trrenavam_connection_pool() {
    local file="$1"
    local env="$2"

    if [ "$env" = "dev" ]; then
        sed -i "s#String url = \"jdbc:postgresql://172.25.136.30:5432/dbveiculos_dev\";#String url = \"jdbc:postgresql://172.25.136.81:5432/dbveiculos_dev\";#" "$file"
    fi
    sed -i "s#this.ds.setUsername( *\"[^\"]*\" *);#this.ds.setUsername( \"$user_db\" );#" "$file"
    sed -i "s#this.ds.setPassword( String.valueOf(this.[^)]*) );#this.ds.setPassword( \"$pwd_db\" );#" "$file"
    sed -i 's#this.ds.setMaxActive( [^)]* );#this.ds.setMaxActive( 1 );#' "$file"
    sed -i 's#this.ds.setMaxIdle( [^)]* );#this.ds.setMaxIdle( 1 );#' "$file"
    sed -i 's#this.ds.setMinIdle( [^)]* );#this.ds.setMinIdle( 1 );#' "$file"
}

modify_trrenavam_transacoes_socket() {
    local file="$1"
    local env="$2"
    if [ "$env" = "dev" ]; then
        sed -i 's#this.host = HostIP.PRODUCAO;#this.host = HostIP.HOMOLOGACAO;#' "$file"
    fi
}

modify_trrenavam_config_transacoes() {
    local file="$1"
    local env="$2"
    sed -i "s/^maxActive=[^ ]*/maxActive=2/" "$file"
    sed -i "s/^maxIdle=[^ ]*/maxIdle=2/" "$file"
    sed -i "s/^minIdle=[^ ]*/minIdle=2/" "$file"
    if [ "$env" = "dev" ]; then
        sed -i 's/url-conexao = jdbc:postgresql:\/\/172.25.136.30:5432\/dbveiculos_dev/url-conexao = jdbc:postgresql:\/\/172.25.136.81:5432\/dbveiculos_dev/g' "$file"
    fi
}

modify_balcaodigital_properties() {
    local file="$1"
    local env="$2"
    if [ -f "$file" ]; then
        sed -i "s/env=prod/env=$env/g" "$file"
    fi
}

checkout_getran "$@"
