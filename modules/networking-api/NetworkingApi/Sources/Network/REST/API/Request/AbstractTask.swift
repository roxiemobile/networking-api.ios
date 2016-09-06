// ----------------------------------------------------------------------------
//
//  AbstractTask.swift
//
//  @author     Denis Kolyasev <KolyasevDA@ekassir.com>
//  @copyright  Copyright (c) 2016, eKassir Ltd. All rights reserved.
//  @link       http://www.ekassir.com/
//
// ----------------------------------------------------------------------------

import Atomic
import SwiftCommons

// ----------------------------------------------------------------------------

public class AbstractTask<Ti: HttpBody, To>: Task<Ti, To>, Cancellable
{
// MARK: - Construction

    public init(builder: AbstractTaskBuilder<Ti, To>)
    {
        // Init instance variables
        self.tag = builder.tag
        self.requestEntity = builder.requestEntity
    }

// MARK: - Properties

    /**
    * The tag associated with a task.
    */
    override public func getTag() -> String {
        return self.tag
    }

    /**
     * The original request entity.
     */
    override public func getRequestEntity() -> RequestEntity<Ti> {
        return self.requestEntity
    }

// MARK: - Functions

    /**
    * Synchronously send the request and return its response.
    */
    public override func execute(callback: Callback<Ti, To>?)
    {
        var shouldExecute = true
        var result: CallResult<To>?

        if let callback = callback {
            shouldExecute = callback.onShouldExecute(self)
        }

        if shouldExecute {
            result = call()
        }

        // Yielding result to listener
        if let callback = callback where shouldExecute {
            yieldResult(result, callback: callback)
        }
    }

    public override func enqueue(callback: Callback<Ti, To>?, callbackOnUiThread: Bool) -> Cancellable {
        return TaskQueue.enqueue(self, callback: callback, callbackOnUiThread: callbackOnUiThread)
    }

    /**
     * Performs the request and returns the response.
     * May return null if this call was canceled.
     */
    final func call() -> CallResult<To>?
    {
        mdc_assert(!(NSThread.isMainThread()), message: "This method must not be called from the main thread!")
        var result: CallResult<To>?

        // Send request to the server
        let httpResult = callExecute()
        var error: RestApiError?

        // Are HTTP response is still needed?
        if !isCancelled()
        {
            // Handle HTTP response
            switch httpResult
            {
                case .Success(let entity):
                    // Create a new call result
                    if let status = entity.status where status.is2xxSuccessful() {
                        result = onResult(.Success(entity))
                    }
                    else {
                        let cause = ResponseError(entity: entity)
                        // Build application layer error
                        error = ApplicationLayerError(cause: cause)
                    }

                case .Failure(let cause):
                    var cause = cause

                    // Wrap up HTTP connection error
                    if isConnectionError(cause) {
                        cause = ConnectionError(cause: cause)
                    }

                    // Build transport layer error
                    error = TransportLayerError(cause: cause)
            }

            // Handle error
            if let error = error {
                result = .Failure(error)
            }
        }

        // Done
        return result
    }

    public func callExecute() -> HttpResult {
        mdc_abstractFunction()
    }

    public func newClient() -> RestApiClient
    {
        // Create/init HTTP client
        let builder = RestApiClientBuilder()
                // Set the timeout until a connection is established
                .connectTimeout(NetworkConfig.Timeout.Connection)
                // Set the default socket timeout which is the timeout for waiting for data
                .requestTimeout(NetworkConfig.Timeout.Request)
                // Handle redirects
                .redirectHandler(newRedirectHandler())

        // Done
        return builder.build()
    }

    func newRedirectHandler() -> RedirectHandler? {
        return nil
    }

    public func newRequestEntity(route: HttpRoute) -> RequestEntity<HttpBody>
    {
        let entity = self.requestEntity

        // Create HTTP request entity
        return BasicRequestEntityBuilder(entity: entity, body: entity.body)
                .url(route.url)
                .headers(httpHeaders())
                .build()
    }

    func httpHeaders() -> HttpHeaders {
        return HttpHeadersUtils.merge(Inner.DefaultHttpHeaders, self.requestEntity.headers)
    }

    public func onResult(httpResult: CallResult<NSData>) -> CallResult<To> {
        mdc_abstractFunction()
    }

    public override func clone() -> Task<Ti, To> {
        return newBuilder().build()
    }

    public func newBuilder() -> TaskBuilder<Ti, To> {
        mdc_abstractFunction()
    }

    public func isCancelled() -> Bool {
        return self.cancelled.value
    }

    public func cancel() -> Bool {
        return !(self.cancelled.swap(true))
    }

// MARK: - Private Functions

    private func isConnectionError(error: ErrorType) -> Bool {
        return ((error as NSError).domain == NSURLErrorDomain || (error as NSError).domain == kCFErrorDomainCFNetwork as NSString)
    }

    private func yieldResult(result: CallResult<To>?, callback: Callback<Ti, To>)
    {
        if !isCancelled()
        {
            if let result = result
            {
                switch result
                {
                    case .Success(let entity):
                        callback.onResponse(self, entity: entity)

                    case .Failure(let error):
                        callback.onFailure(self, error: error)
                }
            }
            else {
                mdc_fatalError("!isCancelled() && (result == null)")
            }
        }
        else {
            callback.onCancel(self)
        }
    }

// MARK: - Inner Types

    public typealias TaskTi = Ti

    public typealias TaskTo = To

    private typealias Inner = AbstractTaskInner

// MARK: - Variables

    private let tag: String

    private let requestEntity: RequestEntity<Ti>

    private let cancelled = Atomic<Bool>(false)

}

// ----------------------------------------------------------------------------

private struct AbstractTaskInner
{
// MARK: - Constants

    static let DefaultHttpHeaders = HttpHeaders([
        HttpHeaders.Header.Accept: MediaType.ApplicationVndEkassirJsonValue + ", " + MediaType.ApplicationJsonValue
    ])

}

// ----------------------------------------------------------------------------

public class AbstractTaskBuilder<Ti, To>: TaskBuilder<Ti, To>
{
// MARK: - Construction

    public override init()
    {
        // Init instance variables
        self.tag = nil
        self.requestEntity = nil
    }

    public init(task: Task<Ti, To>)
    {
        // Init instance variables
        self.tag = task.getTag()
        self.requestEntity = task.getRequestEntity()
    }

// MARK: - Properties

    public override func getTag() -> String {
        return self.tag
    }

    public override func getRequestEntity() -> RequestEntity<Ti> {
        return self.requestEntity
    }

// MARK: - Functions

    public func tag(tag: String) -> Self
    {
        self.tag = tag
        return self
    }

    public func requestEntity(requestEntity: RequestEntity<Ti>) -> Self
    {
        self.requestEntity = requestEntity
        return self
    }

    public override func build() -> Task<Ti, To>
    {
        checkInvalidState()
        return newTask()
    }

    public func checkInvalidState()
    {
        mdc_assert(self.tag != nil)
        mdc_assert(self.requestEntity != nil)
    }

    public func newTask() -> Task<Ti, To> {
        mdc_abstractFunction()
    }

// MARK: - Variables

    private var tag: String!

    private var requestEntity: RequestEntity<Ti>!

}

// ----------------------------------------------------------------------------
