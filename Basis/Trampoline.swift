//
//  Trampoline.swift
//  Basis
//
//  Created by Robert Widmann on 12/20/14.
//  Copyright (c) 2014 Robert Widmann. All rights reserved.
//

/// Represents a computation that either produces a value (pure) or branches (suspend).  Trampolines
/// allow computations that would otherwise use a large amount of stack space to instead trade that
/// cost to the much larger heap and evaluate in constant stack space.
///
/// Evaluation of the tree is based on the Codense Monad outlined in "Stackless Scala With Free 
/// Monads" by Rúnar Óli Bjarnason ~( http://blog.higher-order.com/assets/trampolines.pdf ) with the
/// added benefit of Trampoline itself becoming a Monad.
public struct Trampoline<T> {
	private let t : FreeId<T>
	
	private init(_ t : FreeId<T>) {
		self.t = t
	}
	
	public func run() -> T {
		return t.run()
	}
}

/// Lifts a pure value into a trampoline.
///
/// Add a leaf to the computation tree of a Trampoline.
public func now<T>(x : T) -> Trampoline<T> {
	return Trampoline(Pure(x: x))
}

/// Suspends a sub-computation that yields another Trampoline for evaluation later.
///
/// Adds a branch to the computation tree of a Trampoline.
public func later<T>(x : @autoclosure() -> Trampoline<T>) -> Trampoline<T> {
	return Trampoline(Suspend(s: Box(x)))
}

extension Trampoline : Functor {
	typealias A = T
	typealias B = Swift.Any
	
	typealias FB = Trampoline<B>
	
	public static func fmap<B>(f : T -> B) -> Trampoline<T> -> Trampoline<B> {
		return { b in Trampoline<B>(b.t.flatMap({ x in Pure(x: f(x)) })) }
	}
}

public func <%><A, B>(f : A -> B, b : Trampoline<A>) -> Trampoline<B> {
	return Trampoline.fmap(f)(b)
}

public func <%<A, B>(a : A, b : Trampoline<B>) -> Trampoline<A> {
	return (curry(<%>) • const)(a)(b)
}

extension Trampoline : Applicative {
	typealias FAB = Trampoline<A -> B>
	
	public static func pure<A>(a : A) -> Trampoline<A> {
		return Trampoline<A>(Pure(x: a))
	}
}

public func <*><A, B>(stfn: Trampoline<A -> B>, st: Trampoline<A>) -> Trampoline<B> {
	return Trampoline(stfn.t.flatMap({ f in
		return st.t.flatMap({ a in
			return Pure(x: f(a))
		})
	}))
}

public func *><A, B>(a : Trampoline<A>, b : Trampoline<B>) -> Trampoline<B> {
	return const(id) <%> a <*> b
}

public func <*<A, B>(a : Trampoline<A>, b : Trampoline<B>) -> Trampoline<A> {
	return const <%> a <*> b
}

extension Trampoline : Monad {
	public func bind<B>(f: A -> Trampoline<B>) -> Trampoline<B> {
		return Trampoline<B>(self.t.flatMap({ x in f(x).t }))
	}
}

public func >>-<A, B>(x : Trampoline<A>, f : A -> Trampoline<B>) -> Trampoline<B> {
	return x.bind(f)
}

public func >><A, B>(x : Trampoline<A>, y : Trampoline<B>) -> Trampoline<B> {
	return x.bind({ (_) in
		return y
	})
}

/// Based on "Stackless Scala With Free Monads" by Rúnar Óli Bjarnason 
/// http://blog.higher-order.com/assets/trampolines.pdf
///
/// Codense implementation with catamorphisms inspired by FunctionalJava
/// https://github.com/functionaljava/functionaljava
private class FreeId<T> {
	func resume() -> Either<Box<() -> Trampoline<T>>, T> {
		return undefined()
	}
	
	func run() -> T {
		var current = self
		while true {
			switch current.resume().destruct() {
				case .Left(let ba):
					current = ba.unBox().unBox()().t
				case .Right(let bb):
					return bb.unBox()
			}
		}
	}
	
	func fold<R>(norm : FreeId<T> -> R, codense : Codensity<T> -> R) -> R {
		return undefined()
	}
	
	func normalFold<R>(pure : T -> R, suspend: Box<() -> Trampoline<T>> -> R) -> R {
		return undefined()
	}
	
	func flatMap<B>(f : T -> FreeId<B>) -> FreeId<B> {
		return liftCodense(self, f)
	}
}

private class Pure<T> : FreeId<T> {
	let val : T
	
	init(x : T) {
		self.val = x
	}
	
	private override func fold<R>(norm: FreeId<T> -> R, codense : Codensity<T> -> R) -> R {
		return norm(self)
	}
	
	private override func normalFold<R>(pure : T -> R, suspend : Box<() -> Trampoline<T>> -> R) -> R {
		return pure(self.val)
	}
	
	private override func resume() -> Either<Box<() -> Trampoline<T>>, T> {
		return Either.right(self.val)
	}
}

private class Suspend<T> : FreeId<T> {
	let suspension : Box<() -> Trampoline<T>>
	
	init(s : Box<() -> Trampoline<T>>) {
		self.suspension = s
	}
	
	private override func fold<R>(norm : FreeId<T> -> R, codense : Codensity<T> -> R) -> R {
		return norm(self)
	}
	
	private override func normalFold<R>(pure : T -> R, suspend : Box<() -> Trampoline<T>> -> R) -> R {
		return suspend(self.suspension)
	}
	
	private override func resume() -> Either<Box<() -> Trampoline<T>>, T> {
		return Either.left(self.suspension)
	}
}

/// There's got to be a better way to do this...
private func liftCodense<A, B>(a : FreeId<A>, k : A -> FreeId<B>) -> Codensity<B> {
	return Codensity<B>(sub: unsafeCoerce(a), unsafeCoerce(k))
}

private class Codensity<T> : FreeId<T> {
	let sub : FreeId<T>
	let k : T -> FreeId<T>
	
	private override func fold<R>(norm : FreeId<T> -> R, codense : Codensity<T> -> R) -> R {
		return codense(self)
	}
	
	init(sub : FreeId<T>, k : T -> FreeId<T>) {
		self.sub = sub
		self.k = k
	}
	
	private override func flatMap<B>(f: T -> FreeId<B>) -> FreeId<B> {
		return liftCodense(sub, { o in later(Trampoline(self.k(o).flatMap(f))).t })
	}
		
	private override func resume() -> Either<Box<() -> Trampoline<T>>, T> {
		let e : Box<() -> Trampoline<T>> = either({ p in 
			Box.fmap({ ot in 
				ot().t.fold({ o in
					{ o.normalFold({ obj in Trampoline(self.k(obj)) }, { t in t.unBox()() }) }
				}, 
				{ c in 
					{ Trampoline(liftCodense(c.sub, { o in c.k(o).flatMap(self.k) })) }
				}) 
			})(p) 
		})({ o in 
			return Box<() -> Trampoline<T>>({ Trampoline(self.k(o)) }) 
		})(self.sub.resume())

		return Either<Box<() -> Trampoline<T>>, T>.left(e)
	}
}
