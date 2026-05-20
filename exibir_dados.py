import psycopg2

def exibir_pedidos():
    conexao = None
    try:
        # 1. Configurando a conexão com o banco de dados
        conexao = psycopg2.connect(
            host="localhost",
            port="5434",
            database="loja",
            user="admin",
            password="senha_secreta"
        )
        
        # O bloco 'with' garante o fechamento automático do cursor
        with conexao.cursor() as cursor:
            # 2. Nossa consulta SQL cruzando as tabelas
            query = """
                SELECT clientes.nome, clientes.email, pedidos.produto, pedidos.valor
                FROM clientes
                JOIN pedidos ON clientes.id = pedidos.cliente_id;
            """
            
            cursor.execute(query)
            registros = cursor.fetchall()

            print("\n--- 📦 RELATÓRIO DE VENDAS ---")
            for linha in registros:
                nome, email, produto, valor = linha
                print(f"👤 Cliente: {nome} ({email}) | 🛒 Comprou: {produto} | 💰 Valor: R$ {valor:.2f}")
            
    except (Exception, psycopg2.Error) as erro:
        print("❌ Erro ao conectar no PostgreSQL:", erro)
    finally:
        if conexao is not None:
            conexao.close()
            print("------------------------------")
            print("🔒 Conexão com o banco encerrada.\n")

if __name__ == "__main__":
    exibir_pedidos()