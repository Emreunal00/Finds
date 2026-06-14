import SwiftUI

struct MediaDetailDestination: View {
    let item: Movie

    var body: some View {
        if item.isBook {
            BookDetailView(book: item)
        } else {
            MovieDetailView(movie: item)
        }
    }
}

