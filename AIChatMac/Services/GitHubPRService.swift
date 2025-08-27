//
//  GitHubPRService.swift
//  AIChatMac
//
//  Created by Николай Игнатов on 19.08.2025.
//

import Foundation

final class GitHubPRService {
    let githubToken: String
    private let baseURL = "https://api.github.com"
    
    init(githubToken: String) {
        self.githubToken = githubToken
    }
    
    // MARK: - URL Parsing
    
    func parseGitHubPRURL(_ urlString: String) -> (owner: String, repo: String, prNumber: Int)? {
        // Поддерживаемые форматы:
        // https://github.com/owner/repo/pull/123
        // https://github.com/owner/repo/pull/123/files
        // https://github.com/owner/repo/pull/123#issuecomment-456
        // @https://github.com/owner/repo/pull/123
        
        // Очищаем URL от лишних символов в начале
        var cleanURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Убираем символ @ в начале, если есть
        if cleanURLString.hasPrefix("@") {
            cleanURLString = String(cleanURLString.dropFirst())
        }
        
        // Убираем пробелы в начале, если есть
        cleanURLString = cleanURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let url = URL(string: cleanURLString),
              url.host == "github.com" else {
            return nil
        }
        
        let components = url.pathComponents.filter { !$0.isEmpty }
        
        // Убираем первый элемент, если это "/"
        let cleanComponents = components.first == "/" ? Array(components.dropFirst()) : components
        
        guard cleanComponents.count >= 4,
              cleanComponents[2] == "pull",
              let prNumber = Int(cleanComponents[3]) else {
            return nil
        }
        
        let owner = cleanComponents[0]
        let repo = cleanComponents[1]
        
        return (owner: owner, repo: repo, prNumber: prNumber)
    }
    
    // MARK: - Pull Request Operations
    
    func fetchPullRequest(owner: String, repo: String, prNumber: Int) async -> Result<PullRequest, Error> {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls/\(prNumber)") else {
            return .failure(GitHubError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubError.invalidResponse)
            }
            
            if httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let pullRequest = try decoder.decode(PullRequest.self, from: data)
                return .success(pullRequest)
            } else {
                return .failure(GitHubError.httpError(httpResponse.statusCode))
            }
        } catch {
            return .failure(error)
        }
    }
    
    func fetchPullRequestFiles(owner: String, repo: String, prNumber: Int) async -> Result<[PRFile], Error> {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls/\(prNumber)/files") else {
            return .failure(GitHubError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubError.invalidResponse)
            }
            
            if httpResponse.statusCode == 200 {
                let files = try JSONDecoder().decode([PRFile].self, from: data)
                return .success(files)
            } else {
                return .failure(GitHubError.httpError(httpResponse.statusCode))
            }
        } catch {
            return .failure(error)
        }
    }
    
    func fetchPullRequestDiff(owner: String, repo: String, prNumber: Int) async -> Result<String, Error> {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls/\(prNumber)") else {
            return .failure(GitHubError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3.diff", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubError.invalidResponse)
            }
            
            if httpResponse.statusCode == 200 {
                guard let diffString = String(data: data, encoding: .utf8) else {
                    return .failure(GitHubError.invalidData)
                }
                return .success(diffString)
            } else {
                return .failure(GitHubError.httpError(httpResponse.statusCode))
            }
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - Issue Operations
    
    func createIssue(owner: String, repo: String, issue: GitHubIssueRequest) async -> Result<GitHubIssueResponse, Error> {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues") else {
            return .failure(GitHubError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONEncoder().encode(issue)
            request.httpBody = jsonData
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubError.invalidResponse)
            }
            
            if httpResponse.statusCode == 201 {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let issueResponse = try decoder.decode(GitHubIssueResponse.self, from: data)
                return .success(issueResponse)
            } else {
                return .failure(GitHubError.httpError(httpResponse.statusCode))
            }
        } catch {
            return .failure(error)
        }
    }
    
    func addCommentToPR(owner: String, repo: String, prNumber: Int, comment: String) async -> Result<GitHubComment, Error> {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues/\(prNumber)/comments") else {
            return .failure(GitHubError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let commentData = ["body": comment]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: commentData)
            request.httpBody = jsonData
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubError.invalidResponse)
            }
            
            if httpResponse.statusCode == 201 {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let comment = try decoder.decode(GitHubComment.self, from: data)
                return .success(comment)
            } else {
                return .failure(GitHubError.httpError(httpResponse.statusCode))
            }
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - File Content
    
    func fetchFileContent(owner: String, repo: String, path: String, ref: String) async -> Result<String, Error> {
        let url = "https://api.github.com/repos/\(owner)/\(repo)/contents/\(path)?ref=\(ref)"
        
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubError.networkError)
            }
            
            if httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                let content = try decoder.decode(GitHubContent.self, from: data)
                
                // Декодируем содержимое из base64
                guard let contentData = Data(base64Encoded: content.content),
                      let contentString = String(data: contentData, encoding: .utf8) else {
                    return .failure(GitHubError.decodingError)
                }
                
                return .success(contentString)
            } else {
                return .failure(GitHubError.httpError(httpResponse.statusCode))
            }
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - Branch and Commit Operations
    
    func createBranch(owner: String, repo: String, branchName: String, baseBranch: String) async -> Result<Void, Error> {
        // Сначала получаем SHA последнего коммита в базовой ветке
        let refUrl = "https://api.github.com/repos/\(owner)/\(repo)/git/refs/heads/\(baseBranch)"
        
        var refRequest = URLRequest(url: URL(string: refUrl)!)
        refRequest.httpMethod = "GET"
        refRequest.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        refRequest.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: refRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubError.networkError)
            }
            
            if httpResponse.statusCode != 200 {
                return .failure(GitHubError.httpError(httpResponse.statusCode))
            }
            
            let decoder = JSONDecoder()
            let ref = try decoder.decode(GitHubRef.self, from: data)
            
            // Создаем новую ветку
            let createBranchUrl = "https://api.github.com/repos/\(owner)/\(repo)/git/refs"
            var createRequest = URLRequest(url: URL(string: createBranchUrl)!)
            createRequest.httpMethod = "POST"
            createRequest.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
            createRequest.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let payload = [
                "ref": "refs/heads/\(branchName)",
                "sha": ref.object.sha
            ]
            
            createRequest.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            
            let (createData, createResponse) = try await URLSession.shared.data(for: createRequest)
            
            guard let createHttpResponse = createResponse as? HTTPURLResponse else {
                return .failure(GitHubError.networkError)
            }
            
            if createHttpResponse.statusCode == 201 {
                print("✅ Ветка \(branchName) успешно создана")
                return .success(())
            } else {
                let errorData = String(data: createData, encoding: .utf8) ?? "Unknown error"
                print("❌ GitHub API ошибка \(createHttpResponse.statusCode): \(errorData)")
                print("📋 Попытка создания ветки: \(branchName) от \(baseBranch)")
                
                // Если ветка уже существует, считаем это успехом
                if createHttpResponse.statusCode == 422 && errorData.contains("already exists") {
                    print("⚠️ Ветка \(branchName) уже существует, продолжаем...")
                    return .success(())
                }
                
                return .failure(GitHubError.httpError(createHttpResponse.statusCode))
            }
        } catch {
            return .failure(error)
        }
    }
    
    func createCommit(
        owner: String,
        repo: String,
        branchName: String,
        filePath: String,
        content: String,
        commitMessage: String
    ) async -> Result<Void, Error> {
        
        // Получаем текущий blob для файла
        let blobUrl = "https://api.github.com/repos/\(owner)/\(repo)/git/blobs"
        var blobRequest = URLRequest(url: URL(string: blobUrl)!)
        blobRequest.httpMethod = "POST"
        blobRequest.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        blobRequest.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        blobRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let blobPayload = [
            "content": content,
            "encoding": "utf-8"
        ]
        
        blobRequest.httpBody = try? JSONSerialization.data(withJSONObject: blobPayload)
        
        do {
            let (blobData, blobResponse) = try await URLSession.shared.data(for: blobRequest)
            
            guard let blobHttpResponse = blobResponse as? HTTPURLResponse else {
                return .failure(GitHubError.networkError)
            }
            
            if blobHttpResponse.statusCode != 201 {
                let errorData = String(data: blobData, encoding: .utf8) ?? "Unknown error"
                print("❌ GitHub API ошибка \(blobHttpResponse.statusCode): \(errorData)")
                return .failure(GitHubError.httpError(blobHttpResponse.statusCode))
            }
            
            let decoder = JSONDecoder()
            let blob: GitHubBlob
            do {
                blob = try decoder.decode(GitHubBlob.self, from: blobData)
                print("✅ Blob создан успешно: \(blob.sha)")
            } catch {
                let responseString = String(data: blobData, encoding: .utf8) ?? "Unknown"
                print("❌ Ошибка декодирования blob: \(error)")
                print("📋 Ответ API: \(responseString)")
                return .failure(error)
            }
            
            // Получаем текущее дерево из ветки
            let refUrl = "https://api.github.com/repos/\(owner)/\(repo)/git/refs/heads/\(branchName)"
            var refRequest = URLRequest(url: URL(string: refUrl)!)
            refRequest.httpMethod = "GET"
            refRequest.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
            refRequest.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            
            let (refData, refResponse) = try await URLSession.shared.data(for: refRequest)
            
            guard let refHttpResponse = refResponse as? HTTPURLResponse, refHttpResponse.statusCode == 200 else {
                print("❌ Не удалось получить текущую ветку")
                return .failure(GitHubError.httpError((refResponse as? HTTPURLResponse)?.statusCode ?? -1))
            }
            
            let ref = try decoder.decode(GitHubRef.self, from: refData)
            print("✅ Получена текущая ветка: \(ref.object.sha)")
            
            // Получаем дерево из последнего коммита
            let getCommitUrl = "https://api.github.com/repos/\(owner)/\(repo)/git/commits/\(ref.object.sha)"
            var getCommitRequest = URLRequest(url: URL(string: getCommitUrl)!)
            getCommitRequest.httpMethod = "GET"
            getCommitRequest.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
            getCommitRequest.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            
            let (getCommitData, getCommitResponse) = try await URLSession.shared.data(for: getCommitRequest)
            
            guard let getCommitHttpResponse = getCommitResponse as? HTTPURLResponse, getCommitHttpResponse.statusCode == 200 else {
                print("❌ Не удалось получить последний коммит")
                return .failure(GitHubError.httpError((getCommitResponse as? HTTPURLResponse)?.statusCode ?? -1))
            }
            
            let lastCommit = try decoder.decode(GitHubCommit.self, from: getCommitData)
            print("✅ Получен последний коммит: \(lastCommit.sha)")
            
            // Выводим детали коммита для отладки
            if let commitDetails = lastCommit.commit {
                print("📋 Tree SHA: \(commitDetails.tree.sha)")
                print("📋 Commit message: \(commitDetails.message)")
            } else {
                print("⚠️ Commit details отсутствуют")
            }
            
            // Проверяем доступ к репозиторию
            let repoUrl = "https://api.github.com/repos/\(owner)/\(repo)"
            var repoRequest = URLRequest(url: URL(string: repoUrl)!)
            repoRequest.httpMethod = "GET"
            repoRequest.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
            repoRequest.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            
            let (repoData, repoResponse) = try await URLSession.shared.data(for: repoRequest)
            
            guard let repoHttpResponse = repoResponse as? HTTPURLResponse, repoHttpResponse.statusCode == 200 else {
                let errorData = String(data: repoData, encoding: .utf8) ?? "Unknown error"
                print("❌ Не удалось получить информацию о репозитории: \(errorData)")
                return .failure(GitHubError.httpError((repoResponse as? HTTPURLResponse)?.statusCode ?? -1))
            }
            
            print("✅ Доступ к репозиторию подтвержден")
            
            // Создаем новое дерево
            let treeUrl = "https://api.github.com/repos/\(owner)/\(repo)/git/trees"
            var treeRequest = URLRequest(url: URL(string: treeUrl)!)
            treeRequest.httpMethod = "POST"
            treeRequest.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
            treeRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            treeRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            treeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Получаем последний коммит из default branch
            let defaultBranchUrl = "https://api.github.com/repos/\(owner)/\(repo)/commits/main"
            var defaultBranchRequest = URLRequest(url: URL(string: defaultBranchUrl)!)
            defaultBranchRequest.httpMethod = "GET"
            defaultBranchRequest.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
            defaultBranchRequest.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            
            let (defaultBranchData, defaultBranchResponse) = try await URLSession.shared.data(for: defaultBranchRequest)
            
            guard let defaultBranchHttpResponse = defaultBranchResponse as? HTTPURLResponse, defaultBranchHttpResponse.statusCode == 200 else {
                print("❌ Не удалось получить последний коммит из default branch")
                return .failure(GitHubError.httpError((defaultBranchResponse as? HTTPURLResponse)?.statusCode ?? -1))
            }
            
            let defaultBranchCommit = try decoder.decode(GitHubCommit.self, from: defaultBranchData)
            print("✅ Получен коммит из default branch: \(defaultBranchCommit.sha)")
            
            // Получаем tree SHA из коммита
            guard let commitDetails = defaultBranchCommit.commit else {
                print("❌ Не удалось получить commit details из default branch")
                return .failure(GitHubError.apiError("Не удалось получить commit details из default branch"))
            }
            
            let treeSha = commitDetails.tree.sha
            print("📋 Tree SHA из default branch: \(treeSha)")
            print("📋 Default branch commit SHA: \(defaultBranchCommit.sha)")
            
            // Сначала создаем blob, затем используем его SHA в tree
            let newBlobUrl = "https://api.github.com/repos/\(owner)/\(repo)/git/blobs"
            var newBlobRequest = URLRequest(url: URL(string: newBlobUrl)!)
            newBlobRequest.httpMethod = "POST"
            newBlobRequest.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
            newBlobRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            newBlobRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            newBlobRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let newBlobPayload: [String: Any] = [
                "content": content,
                "encoding": "utf8"
            ]
            
            newBlobRequest.httpBody = try? JSONSerialization.data(withJSONObject: newBlobPayload)
            
            let (newBlobData, newBlobResponse) = try await URLSession.shared.data(for: newBlobRequest)
            
            guard let newBlobHttpResponse = newBlobResponse as? HTTPURLResponse else {
                return .failure(GitHubError.networkError)
            }
            
            if newBlobHttpResponse.statusCode != 201 {
                let errorData = String(data: newBlobData, encoding: .utf8) ?? "Unknown error"
                print("❌ GitHub API ошибка при создании blob \(newBlobHttpResponse.statusCode): \(errorData)")
                return .failure(GitHubError.httpError(newBlobHttpResponse.statusCode))
            }
            
            let newBlob: GitHubBlob
            do {
                newBlob = try decoder.decode(GitHubBlob.self, from: newBlobData)
                print("✅ Blob создан успешно: \(newBlob.sha)")
            } catch {
                let responseString = String(data: newBlobData, encoding: .utf8) ?? "Unknown"
                print("❌ Ошибка декодирования blob: \(error)")
                print("📋 Ответ API: \(responseString)")
                return .failure(error)
            }
            
            // Создаем новое дерево с нашим файлом
            // Не используем base_tree, создаем новое дерево с нуля
            let treePayload: [String: Any] = [
                "tree": [
                    [
                        "path": filePath,
                        "mode": "100644",
                        "type": "blob",
                        "sha": newBlob.sha
                    ]
                ]
            ]
            
            print("📋 Создаем новое tree без base_tree")
            print("📋 Tree payload: \(treePayload)")
            
            treeRequest.httpBody = try? JSONSerialization.data(withJSONObject: treePayload)
            
            let (treeData, treeResponse) = try await URLSession.shared.data(for: treeRequest)
            
            print("📋 Tree response status: \((treeResponse as? HTTPURLResponse)?.statusCode ?? -1)")
            print("📋 Tree response data: \(String(data: treeData, encoding: .utf8) ?? "Unknown")")
            
            guard let treeHttpResponse = treeResponse as? HTTPURLResponse, treeHttpResponse.statusCode == 201 else {
                let errorData = String(data: treeData, encoding: .utf8) ?? "Unknown error"
                print("❌ GitHub API ошибка при создании tree: \(errorData)")
                return .failure(GitHubError.httpError((treeResponse as? HTTPURLResponse)?.statusCode ?? -1))
            }
            
            let newTree: GitHubTree
            do {
                newTree = try decoder.decode(GitHubTree.self, from: treeData)
                print("✅ Tree создан успешно: \(newTree.sha)")
            } catch {
                let responseString = String(data: treeData, encoding: .utf8) ?? "Unknown"
                print("❌ Ошибка декодирования tree: \(error)")
                print("📋 Ответ API: \(responseString)")
                return .failure(error)
            }
            
            // Создаем новый коммит
            let commitUrl = "https://api.github.com/repos/\(owner)/\(repo)/git/commits"
            var commitRequest = URLRequest(url: URL(string: commitUrl)!)
            commitRequest.httpMethod = "POST"
            commitRequest.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
            commitRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            commitRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            commitRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let commitPayload: [String: Any] = [
                "message": commitMessage,
                "tree": newTree.sha,
                "parents": [defaultBranchCommit.sha]
            ]
            
            commitRequest.httpBody = try? JSONSerialization.data(withJSONObject: commitPayload)
            
            let (commitData, commitResponse) = try await URLSession.shared.data(for: commitRequest)
            
            guard let commitHttpResponse = commitResponse as? HTTPURLResponse, commitHttpResponse.statusCode == 201 else {
                let errorData = String(data: commitData, encoding: .utf8) ?? "Unknown error"
                print("❌ GitHub API ошибка при создании коммита: \(errorData)")
                return .failure(GitHubError.httpError((commitResponse as? HTTPURLResponse)?.statusCode ?? -1))
            }
            
            let newCommit: GitHubCommit
            do {
                newCommit = try decoder.decode(GitHubCommit.self, from: commitData)
                print("✅ Коммит создан успешно: \(newCommit.sha)")
            } catch {
                let responseString = String(data: commitData, encoding: .utf8) ?? "Unknown"
                print("❌ Ошибка декодирования коммита: \(error)")
                print("📋 Ответ API: \(responseString)")
                return .failure(error)
            }
            
            // Обновляем ветку новым коммитом
            let updateBranchUrl = "https://api.github.com/repos/\(owner)/\(repo)/git/refs/heads/\(branchName)"
            var updateBranchRequest = URLRequest(url: URL(string: updateBranchUrl)!)
            updateBranchRequest.httpMethod = "PATCH"
            updateBranchRequest.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
            updateBranchRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            updateBranchRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            updateBranchRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let updateBranchPayload: [String: Any] = [
                "sha": newCommit.sha
            ]
            
            updateBranchRequest.httpBody = try? JSONSerialization.data(withJSONObject: updateBranchPayload)
            
            let (updateBranchData, updateBranchResponse) = try await URLSession.shared.data(for: updateBranchRequest)
            
            guard let updateBranchHttpResponse = updateBranchResponse as? HTTPURLResponse, updateBranchHttpResponse.statusCode == 200 else {
                let errorData = String(data: updateBranchData, encoding: .utf8) ?? "Unknown error"
                print("❌ GitHub API ошибка при обновлении ветки: \(errorData)")
                return .failure(GitHubError.httpError((updateBranchResponse as? HTTPURLResponse)?.statusCode ?? -1))
            }
            
            print("✅ Ветка обновлена успешно")
            print("✅ Файл создан успешно: \(filePath)")
            print("📋 Создана ветка: \(branchName)")
            print("📋 Создан blob: \(newBlob.sha)")
            print("📋 Создан tree: \(newTree.sha)")
            print("📋 Создан коммит: \(newCommit.sha)")
            
            return .success(())
        } catch {
            return .failure(error)
        }
    }
    
    func createPullRequest(
        owner: String,
        repo: String,
        title: String,
        body: String,
        baseBranch: String,
        headBranch: String
    ) async -> Result<PullRequest, Error> {
        
        let url = "https://api.github.com/repos/\(owner)/\(repo)/pulls"
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = [
            "title": title,
            "body": body,
            "head": headBranch,
            "base": baseBranch
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubError.invalidResponse)
            }
            
            if httpResponse.statusCode == 201 {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let pullRequest = try decoder.decode(PullRequest.self, from: data)
                return .success(pullRequest)
            } else {
                // Детальная обработка ошибок
                let errorData = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ GitHub API ошибка \(httpResponse.statusCode): \(errorData)")
                
                if httpResponse.statusCode == 422 {
                    // 422 обычно означает, что PR уже существует
                    return .failure(GitHubError.apiError("Pull Request уже существует или есть конфликт"))
                } else {
                    return .failure(GitHubError.httpError(httpResponse.statusCode))
                }
            }
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - Pull Request Management
    
    func checkPullRequestExists(
        owner: String,
        repo: String,
        headBranch: String,
        baseBranch: String
    ) async -> Result<Bool, Error> {
        
        let url = "https://api.github.com/repos/\(owner)/\(repo)/pulls?head=\(owner):\(headBranch)&base=\(baseBranch)"
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubError.invalidResponse)
            }
            
            if httpResponse.statusCode == 200 {
                let pullRequests = try JSONDecoder().decode([PullRequest].self, from: data)
                return .success(!pullRequests.isEmpty)
            } else {
                return .failure(GitHubError.httpError(httpResponse.statusCode))
            }
        } catch {
            return .failure(error)
        }
    }
    
    
}

// MARK: - Supporting Models

struct PRFile: Codable {
    let sha: String
    let filename: String
    let status: String
    let additions: Int
    let deletions: Int
    let changes: Int
    let blobUrl: String
    let rawUrl: String
    let contentsUrl: String
    let patch: String?
    
    enum CodingKeys: String, CodingKey {
        case sha, filename, status, additions, deletions, changes
        case blobUrl = "blob_url"
        case rawUrl = "raw_url"
        case contentsUrl = "contents_url"
        case patch
    }
}

struct GitHubIssueResponse: Codable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let htmlUrl: String
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, number, title, body, state
        case htmlUrl = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct GitHubComment: Codable {
    let id: Int
    let body: String
    let user: GitHubUser
    let createdAt: Date
    let updatedAt: Date
    let htmlUrl: String
    
    enum CodingKeys: String, CodingKey {
        case id, body, user
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case htmlUrl = "html_url"
    }
}

enum GitHubError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidData
    case httpError(Int)
    case apiError(String)
    case networkError
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Неверный URL"
        case .invalidResponse:
            return "Неверный ответ от сервера"
        case .invalidData:
            return "Неверные данные"
        case .httpError(let code):
            return "HTTP ошибка: \(code)"
        case .apiError(let message):
            return "API ошибка: \(message)"
        case .networkError:
            return "Ошибка сети"
        case .decodingError:
            return "Ошибка декодирования данных"
        }
    }
}
