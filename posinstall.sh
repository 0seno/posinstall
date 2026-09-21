#!/bin/bash

# Variáveis
help="pinstall - Script de pós-instalação que instala pacotes baseado em um lista predefinda, e \
 configura o sistema utilizando arquivos de um repositório remoto.

usage: pinstall [OPÇÕES]

Opções:
-h Exibe a mensagem de ajuda e sai
-l <installed|missing|all> Apenas exibe quais pacotes da lista estão instalados, faltando ou ambos.
-f <ARQUIVO> Define um arquivo contendo a lista de pacotes (um pacote por linha).
-y Desabilita modo interativo, instalando os pacotes da lista que não estão presentes no sistema,\
 sem perguntar."

skip_stage=0
f_installed=
f_n_installed=

arquivo_lista="$HOME/lista-pacotes" # trocar para $HOME/.config/posinstall/

declare -a instalados
declare -a nao_instalados
declare -a erro

erro[1]="O arquivo que contém a lista de pacotes não existe ou não é legível."
erro[2]="A instalação não pôde ser concluída."
erro[3]="A lista de pacotes não deve ser uma lista vazia."
erro[4]="Opções/argumentos inválidos."
erro[5]="Necessita especificar um arquivo contendo a lista de pacotes"

verde="\033[32m"
vermelho="\033[31m"
color_reset="\033[0m"

# Regex de borda
# Borda início
bi='(^|[[:space:]])'
# Borda fim
bf='([[:space:]]|$)'

# Funções

sair() {
    echo "erro: ${erro[$1]}"
    exit $1
}

# Lê a primeira palavra de cada linha de arquivo_lista, testa se o pacote está ou não instalado,
# populando os arrays instalados e nao_instalados
testar_pacotes() {
    while read -r pacote _; do
        dpkg-query --show -f '${binary:Package}\n' "$pacote" &>/dev/null \
	    && instalados+=("$pacote") \
	    || nao_instalados+=("$pacote")
    done <"$arquivo_lista"
} 2>/dev/null

instalar_pacotes() {
    if [[ "$(id -u)" -eq 0 ]]; then
        { apt update && apt install -y "${nao_instalados[@]}"; } || sair 2
    else
        { sudo apt update && sudo apt install -y "${nao_instalados[@]}"; } || sair 2
    fi
}

exibir_instalados() {
    for i in "${instalados[@]}"; do
        echo -e "$i ${verde}- Instalado${color_reset}"
    done
}

exibir_n_instalados() {
    for i in "${nao_instalados[@]}"; do
        echo -e "$i ${vermelho}- Não instalado${color_reset}"
    done
}

help_usage() { echo "$help"; }

estagio2() {
    echo "estágio 2 em andamento"
}

# Main

# Testa opções
for ((i=1; i<="$#"; i++)); do
    # Testa opções -h e --help, se sucesso, utiliza a função de ajuda
    if [[ "${@:i:1}" =~ $bi(-h|--help)$bf ]]; then
        help_usage
        exit 0
    # Testa opções -s e --skip, se sucesso, define skip_stage=1
    elif [[ "${@:i:1}" =~ $bi(-s|--skip)$bf ]]; then
        echo "Pulando Estágio 1..."
        skip_stage=1
        break
    # Testa opções -f e --file, se sucesso, define arquivo_lista com o arquivo especificado
    elif [[ "${@:i:1}" =~ $bi(-f|--file)$bf ]]; then
        arquivo_lista="${@:$((i+1)):1}"
    # Testa se o argumento é o arquivo_lista e se é precedido pelas opções -f ou --file
    elif [[ "${@:i:1}" == "$arquivo_lista" ]]; then
        ! [[ "${@:$((i-1)):1}" =~ $bi(-f|--file)$bf ]] && { help_usage; sair 4; }
        true
    # Testa as opções -l e --list, se sucesso, testa se essas opções possuem ou não argumentos
    elif [[ "${@:i:1}" =~ $bi(-l|--list)$bf ]]; then
        if [[ -z "${@:$((i+1)):1}" ]] \
            || [[ "${@:$((i+1)):1}" =~ $bi(-h|--help|-s|--skip|-f|--file|-y|--yes)$bf ]]; then
            f_installed='true'
            f_n_installed='true'
        elif [[ "${@:$((i+1)):1}" == "all" ]]; then
            f_installed='true'
            f_n_installed='true'
        elif [[ "${@:$((i+1)):1}" == "installed" ]]; then
            f_installed='true'
        elif [[ "${@:$((i+1)):1}" == "missing" ]]; then
            f_n_installed='true'
        # Chama a função de ajuda e sai com erro caso haja algum argumento não esperado
        else
            help_usage
            sair 4
        fi
    # Chama a função testar pacotes, populando os arrays instalados e nao_instalados
    testar_pacotes
    # Testa os argumentos das opções -l e --list
    elif [[ "${@:i:1}" =~ $bi(all|installed|missing)$bf ]]; then
        ! [[ "${@:$((i-1)):1}" =~ $bi(-l|--list)$bf ]] && sair 4
        true
    # Testa as opções -y e --yes
    elif [[ "${@:i:1}" =~ $bi(-y|--yes)$bf ]]; then
        testar_pacotes
        instalar_pacotes
        skip_stage=1
    # Chama a função de ajuda e sai com erro caso haja alguma opção não esperada
    else
        help_usage
        sair 4
    fi
done

# Estágio 1 (Ignorado se skip_stage=1)
if [[ "$skip_stage" -eq 0 ]]; then
    echo -e "Estágio 1: Listando e/ou instalando pacotes...\n"
    # Testa se o arquivo é legível
    [[ -r "$arquivo_lista" ]] || { help_usage; sair 1; }
    # Testa se a lista de pacotes está vazia
    [[ -s "$arquivo_lista" ]] || { help_usage; sair 3; }
    # Testa a flag/variável f_installed, se sucesso, chama a função exibir_instalados
    [[ -n $f_installed ]] && exibir_instalados
    # Testa a flag/variável f_n_installed, se sucesso, chama a função exibir_n_instalados
    [[ -n $f_n_installed ]] && exibir_n_instalados
    # Testa se as flags/variáveis f_installed e/ou f_n_installed foram ativadas, se seucesso, sai
    [[ -n $f_installed || -n $f_n_installed ]] && exit 0
    # Chamando a função testar_pacotes
    testar_pacotes
    # Chamando as funções de exibir pacotes
    exibir_instalados
    exibir_n_instalados
    # Instalação interativa (padrão sem opções)
    while true; do
        read -p "Deseja instalar os pacotes não instalados?[S/n] " opt
        case $opt in
            s|S|y|Y|'')
                instalar_pacotes
                break
                ;;
	    n|N)
                echo "Os pacotes não serão instalados. Abortando..."
                break
                ;;
	    *)
                true
                ;;
        esac
    done
else
    echo -e "\nEstágio 2:\n"
fi
